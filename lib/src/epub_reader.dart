import 'dart:async';
import 'dart:io' as IO;

import 'package:archive/archive.dart';

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_text_content_file.dart';
import 'readers/content_reader.dart';
import 'readers/schema_reader.dart';
import 'ref_entities/epub_book_ref.dart';
import 'ref_entities/epub_byte_content_file_ref.dart';
import 'ref_entities/epub_chapter_ref.dart';
import 'ref_entities/epub_content_file_ref.dart';
import 'ref_entities/epub_content_ref.dart';
import 'ref_entities/epub_text_content_file_ref.dart';
import 'schema/opf/epub_metadata_creator.dart';

class EpubReader {
  /// Opens the book asynchronously without reading its content. Holds the handle to the EPUB file.
  static Future<EpubBookRef> OpenBookAsync(String filePath) async {
    var targetFile = new IO.File(filePath);
    if (!(await targetFile.exists()))
      throw new Exception("Specified epub file not found: ${filePath}");

    List<int> bytes = await targetFile.readAsBytes();
    Archive epubArchive = new ZipDecoder().decodeBytes(bytes);

    EpubBookRef bookRef = new EpubBookRef(epubArchive);
    bookRef.FilePath = filePath;
    bookRef.Schema = await SchemaReader.ReadSchemaAsync(epubArchive);
    bookRef.Title = bookRef.Schema.Package.Metadata.Titles
        .firstWhere((String name) => true, orElse: () => "");
    bookRef.AuthorList = bookRef.Schema.Package.Metadata.Creators
        .map((EpubMetadataCreator creator) => creator.Creator)
        .toList();
    bookRef.Author = bookRef.AuthorList.join(", ");
    bookRef.Content = await ContentReader.ParseContentMap(bookRef);
    return bookRef;
  }

  /// Opens the book asynchronously and reads all of its content into the memory. Does not hold the handle to the EPUB file.
  static Future<EpubBook> ReadBookAsync(String filePath) async {
    EpubBook result = new EpubBook();

    EpubBookRef epubBookRef = await OpenBookAsync(filePath);
    result.FilePath = epubBookRef.FilePath;
    result.Schema = epubBookRef.Schema;
    result.Title = epubBookRef.Title;
    result.AuthorList = epubBookRef.AuthorList;
    result.Author = epubBookRef.Author;
    result.Content = await ReadContent(epubBookRef.Content);
    result.CoverImage = await epubBookRef.ReadCoverAsync();
    List<EpubChapterRef> chapterRefs = await epubBookRef.GetChaptersAsync();
    result.Chapters = await readChapters(chapterRefs);

    return result;
  }

  static Future<EpubContent> ReadContent(EpubContentRef contentRef) async {
    EpubContent result = new EpubContent();
    result.Html = await readTextContentFiles(contentRef.Html);
    result.Css = await readTextContentFiles(contentRef.Css);
    result.Images = await readByteContentFiles(contentRef.Images);
    result.Fonts = await readByteContentFiles(contentRef.Fonts);
    result.AllFiles = new Map<String, EpubContentFile>();

    result.Html.forEach((String key, EpubTextContentFile value) {
      result.AllFiles[key] = value;
    });
    result.Css.forEach((String key, EpubTextContentFile value) {
      result.AllFiles[key] = value;
    });

    result.Images.forEach((String key, EpubByteContentFile value) {
      result.AllFiles[key] = value;
    });
    result.Fonts.forEach((String key, EpubByteContentFile value) {
      result.AllFiles[key] = value;
    });

    await contentRef.AllFiles
        .forEach((String key, EpubContentFileRef value) async {
      if (!result.AllFiles.containsKey(key)) {
        result.AllFiles[key] = await readByteContentFile(value);
      }
    });

    return result;
  }

  static Future<Map<String, EpubTextContentFile>> readTextContentFiles(
      Map<String, EpubTextContentFileRef> textContentFileRefs) async {
    Map<String, EpubTextContentFile> result =
        new Map<String, EpubTextContentFile>();
    await textContentFileRefs
        .forEach((String key, EpubContentFileRef value) async {
      EpubTextContentFile textContentFile = new EpubTextContentFile();
      textContentFile.FileName = value.FileName;
      textContentFile.ContentType = value.ContentType;
      textContentFile.ContentMimeType = value.ContentMimeType;
      textContentFile.Content = await value.ReadContentAsTextAsync();
      result[key] = textContentFile;
    });
    return result;
  }

  static Future<Map<String, EpubByteContentFile>> readByteContentFiles(
      Map<String, EpubByteContentFileRef> byteContentFileRefs) async {
    Map<String, EpubByteContentFile> result =
        new Map<String, EpubByteContentFile>();
    byteContentFileRefs
        .forEach((String key, EpubByteContentFileRef value) async {
      result[key] = await readByteContentFile(value);
    });
    return result;
  }

  static Future<EpubByteContentFile> readByteContentFile(
      EpubContentFileRef contentFileRef) async {
    EpubByteContentFile result = new EpubByteContentFile();

    result.FileName = contentFileRef.FileName;
    result.ContentType = contentFileRef.ContentType;
    result.ContentMimeType = contentFileRef.ContentMimeType;
    result.Content = await contentFileRef.ReadContentAsBytesAsync();

    return result;
  }

  static Future<List<EpubChapter>> readChapters(
      List<EpubChapterRef> chapterRefs) async {
    List<EpubChapter> result = new List<EpubChapter>();
    await chapterRefs.forEach((EpubChapterRef chapterRef) async {
      EpubChapter chapter = new EpubChapter();
      
      chapter.Title = chapterRef.Title;
      chapter.ContentFileName = chapterRef.ContentFileName;
      chapter.Anchor = chapterRef.Anchor;    
      chapter.HtmlContent = await chapterRef.ReadHtmlContentAsync();
      chapter.SubChapters = await readChapters(chapterRef.SubChapters);
      
      result.add(chapter);
    });
    return result;
  }
}
