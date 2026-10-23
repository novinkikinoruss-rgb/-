-- Private arbitrary-format trip attachments. Original filenames stay in metadata.
update storage.buckets set allowed_mime_types=null where id='respectlogistic-trip-documents';
notify pgrst,'reload schema';
