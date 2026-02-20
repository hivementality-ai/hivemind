# Slack File Upload Support

## Overview

The SlackAdapter has been extended to support file uploads via Slack's `files.upload` API. This allows the Hivemind system to send files (images, documents, etc.) directly to Slack channels.

## Features

- **Local File Upload**: Upload files from the server filesystem
- **Remote URL Download & Upload**: Download files from remote URLs and upload to Slack
- **File Type Detection**: Automatic file type detection based on filename extension
- **Metadata Support**: Include file titles and initial comments with uploads
- **Thread Support**: Upload files directly to specific message threads
- **Size Validation**: Validate file sizes against Slack's limits (20GB max)
- **Error Handling**: Comprehensive error handling for network, file system, and API errors

## Architecture

### File Upload Flow

```
send_message(file_path or url)
    ↓
Read/Download File
    ↓
Validate File Size
    ↓
Determine File Type
    ↓
Build Multipart Body
    ↓
Upload via files.upload API
    ↓
Log Outbound Message with Metadata
```

### Key Components

1. **`send_message`** - Entry point that detects file upload parameters
2. **`upload_file`** - Orchestrates the upload process
3. **`read_local_file`** - Reads files from the filesystem with path validation
4. **`download_remote_file`** - Downloads files from remote URLs
5. **`validate_file_size`** - Enforces Slack's file size limits
6. **`determine_filetype`** - Maps file extensions to Slack filetypes
7. **`build_multipart_body`** - Constructs multipart/form-data for upload
8. **`upload_via_multipart`** - Executes the HTTP multipart request

## Usage

### Basic File Upload (Local File)

```ruby
adapter.send_message(
  to: "C123456789",
  content: "Check out this image!",
  file_path: "/path/to/image.png",
  title: "My Image"
)
```

### Upload from Remote URL

```ruby
adapter.send_message(
  to: "C123456789",
  content: "Generated image",
  url: "https://example.com/generated.png"
)
```

### Upload to Thread

```ruby
adapter.send_message(
  to: "C123456789",
  content: "Here's the file",
  file_path: "/path/to/document.pdf",
  thread_ts: "1234567890.000001"
)
```

### With Generated Images

Generated images from the `image_generate` tool can be uploaded by saving to a temporary file:

```ruby
# From image_generate tool result
temp_file = Tempfile.new(['image', '.png'])
temp_file.write(image_data)
temp_file.rewind

adapter.send_message(
  to: channel_id,
  content: "Generated image from AI",
  file_path: temp_file.path,
  title: "AI Generated Image"
)
```

## Parameters

### `send_message` Options for File Uploads

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `to` | String | Yes | Slack channel ID |
| `content` | String | Yes | Message text (used as initial_comment) |
| `file_path` | String | No | Path to local file to upload |
| `url` | String | No | Remote URL to download and upload |
| `title` | String | No | Title for the file in Slack |
| `thread_ts` | String | No | Thread timestamp for threaded uploads |

**Note**: Either `file_path` or `url` must be provided for file uploads.

## File Type Support

The adapter automatically detects Slack file types from file extensions:

| Extension | Slack Type |
|-----------|-----------|
| `.png` | png |
| `.jpg`, `.jpeg` | jpg |
| `.gif` | gif |
| `.pdf` | pdf |
| `.txt` | text |
| `.md` | markdown |
| `.html` | html |
| `.json` | json |
| `.xlsx` | excel |
| `.pptx` | powerpointx |

If the extension is not recognized, Slack will auto-detect the type.

## Size Limits

- **Maximum file size**: 20 GB (per Slack API)
- **Snippet limit**: 1 MB (for editable snippets)

The adapter validates file size before upload and will return an error if the limit is exceeded.

## Error Handling

The adapter provides detailed error messages for various failure scenarios:

- **Missing credentials**: "Slack bot token not configured"
- **File not found**: "Invalid file path"
- **Download failure**: "Failed to download file: HTTP 404"
- **Size exceeded**: "File too large: 25 GB. Max size is 20 GB"
- **API error**: "Slack file upload failed: [error message]"

## Response Format

On successful upload, the adapter returns:

```ruby
{
  success: true,
  data: {
    outbound_message: OutboundMessage,
    response: {
      ok: true,
      file: {
        id: "F123456",
        name: "image.png",
        permalink: "https://example.slack.com/files/U123/F456/image.png"
      }
    }
  }
}
```

The `OutboundMessage` metadata includes:
- `file_id`: Slack file ID
- `file_name`: Uploaded filename
- `file_url`: Slack permalink to the file

## Testing

The SlackAdapter has comprehensive test coverage for file uploads:

```bash
bundle exec rspec spec/services/channels/slack_adapter_spec.rb
```

Test scenarios include:
- Local file uploads
- Remote URL downloads and uploads
- File size validation
- File metadata (title, initial_comment, thread_ts)
- Error handling for missing files and failed downloads
- File type detection
- Multipart body construction

## Security Considerations

1. **Path Validation**: Local file paths are expanded and checked for existence
2. **Directory Traversal Prevention**: Path validation prevents access to files outside the intended directories
3. **Size Limits**: Files exceeding Slack's limits are rejected before upload
4. **Binary Safety**: File content is treated as binary data (no encoding assumptions)

## Integration with Agent Tools

The file upload feature integrates seamlessly with agent tools:

```ruby
# Example: Upload generated image from image_generate tool
image_data = Tools::ImageGenerateExecutor.new(agent).execute(
  prompt: "A cat wearing sunglasses"
)

# Save to temp file and upload
temp_file = Tempfile.new(['generated', '.png'])
temp_file.write(image_data)
temp_file.rewind

adapter.send_message(
  to: channel_id,
  content: "Check out this AI-generated image",
  file_path: temp_file.path,
  title: "Generated Image"
)

temp_file.close
temp_file.unlink
```

## API Details

### Slack files.upload Endpoint

The adapter uses Slack's `files.upload` API with multipart/form-data encoding:

**Endpoint**: `POST https://slack.com/api/files.upload`

**Authentication**: Bearer token in Authorization header

**Parameters**:
- `file` (binary): File content
- `filename` (text): Original filename
- `title` (text): Title in Slack
- `filetype` (text): Slack file type
- `initial_comment` (text): Message text
- `channels` (text): Channel ID(s) to share with
- `thread_ts` (text): Parent message timestamp for threads

**Response**: Slack file object with metadata

## Slack API Documentation

For more details, see: https://api.slack.com/methods/files.upload

## Future Enhancements

Potential improvements for future versions:

1. **Async Uploads**: Background job support for large files
2. **Progress Tracking**: Progress callbacks for long-running uploads
3. **Multiple Files**: Batch upload support
4. **File Deletion**: Support for deleting uploaded files
5. **URL Expiry**: Automatic handling of file expiration
6. **Thumbnail Generation**: Custom thumbnail support for images

## Troubleshooting

### "Slack bot token not configured"
- Ensure the bot token is set in the vault under `channel_credentials:slack_bot_token`

### "Invalid file path"
- Check that the file exists and the path is correct
- Ensure the bot user has read permissions for the file

### "Failed to download file"
- Verify the URL is accessible
- Check network connectivity
- Ensure the remote file exists (HTTP 404 error means file not found)

### "File too large"
- Check the file size against Slack's 20GB limit
- Use `format_bytes` helper to understand actual file size

### File appears but without content
- Verify the file type is recognized by Slack
- Try uploading with an explicit `filetype` parameter
- Check Slack's file type documentation
