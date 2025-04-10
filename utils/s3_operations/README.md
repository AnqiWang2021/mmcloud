# S3 Versioned Operations Tool

This script provides a safe and reliable way to manage versioned objects in Amazon S3. It supports three operations:

- **copy**: Copies all versions of objects from a source prefix to a destination prefix.
- **move**: Copies all versions and then deletes them from the source location (can be used for renaming).
- **delete**: Permanently deletes all versions of objects under a given prefix.

This is useful when working with versioned S3 buckets where standard `aws s3 cp` or `mv` commands only operate on the latest version, leaving older versions behind and potentially incurring unexpected storage costs.

## Features

- Handles all versions of objects in versioned S3 buckets.
- Supports copy, move, and delete operations.
- Operates recursively under a given prefix.
- Ensures that no hidden versions are left behind.
- Supports merging content from source into destination (preserving subfolder structure).
- Automatically strips trailing slashes from all prefixes.
- Creates destination folders if they don't exist (useful for renaming operations).

## Requirements

- Python 3.6 or higher
- `boto3` library (`pip install boto3`, or for those using StatFunGen Lab default setup, `pixi global install --environment python boto3`)
- AWS credentials configured via AWS CLI or environment variables

## Usage

```bash
python version-aware-cleanup.py \
  --operation <copy|move|delete> \
  --source-bucket <bucket-name> \
  --source-prefix <path/in/bucket/> \
  [--dest-bucket <bucket-name>] \
  [--dest-prefix <path/in/bucket/>] \
  [--merge]
```

### Parameters

- `--operation`: The operation to perform (copy, move, or delete).
- `--source-bucket`: Source bucket name.
- `--source-prefix`: Source prefix (folder path).
- `--dest-bucket`: Destination bucket name (required for copy/move).
- `--dest-prefix`: Destination prefix (required for copy/move).
- `--merge`: Optional flag to merge contents of source into destination while preserving subfolder structure (only for copy/move).

### Path Handling

- All trailing slashes (`/`) are automatically stripped from prefixes.
- By default, the source folder name is preserved in the destination path (creating a nested structure).
- With the `--merge` option, contents under the source folder are copied directly to the destination while preserving their subfolder structure.
- Destination folders are created automatically if they don't exist.

## Examples

### Default Copy (Preserving Full Folder Structure)

Copy all versions from `ftp_fgc_xqtl/20250218_ADSP_LD_matrix_APOEblocks_merge` to `ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix`, preserving the complete folder structure:

```bash
python version-aware-cleanup.py \
  --operation copy \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/20250218_ADSP_LD_matrix_APOEblocks_merge \
  --dest-prefix ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix
```

This will create:
```
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/20250218_ADSP_LD_matrix_APOEblocks_merge/
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/20250218_ADSP_LD_matrix_APOEblocks_merge/chr19_42346101_46842901.cor.xz
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/20250218_ADSP_LD_matrix_APOEblocks_merge/chr19_42346101_46842901.cor.xz.bim
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/20250218_ADSP_LD_matrix_APOEblocks_merge/ld_meta_file_apoe.tsv
```

### Merge Copy (Preserving Subfolder Structure)

Copy all versions from `ftp_fgc_xqtl/20250218_ADSP_LD_matrix_APOEblocks_merge` directly into `ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix` while preserving subfolder structure:

```bash
python version-aware-cleanup.py \
  --operation copy \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/20250218_ADSP_LD_matrix_APOEblocks_merge \
  --dest-prefix ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix \
  --merge
```

This will create:
```
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/chr19_42346101_46842901.cor.xz
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/chr19_42346101_46842901.cor.xz.bim
ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/ld_meta_file_apoe.tsv
```

If the source had subfolders like `ftp_fgc_xqtl/20250218_ADSP_LD_matrix_APOEblocks_merge/subset1/file.txt`, it would be copied to `ftp_fgc_xqtl/resource/20240409_ADSP_LD_matrix/subset1/file.txt`.

### Rename (Move Operation)

Rename a folder by moving all versions to a new location:

```bash
python version-aware-cleanup.py \
  --operation move \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/old_folder_name \
  --dest-prefix ftp_fgc_xqtl/new_folder_name
```

This will effectively rename `old_folder_name` to `new_folder_name` while preserving all versions and the full folder hierarchy. The destination prefix will be created automatically if it doesn't exist.

### Move with Merge Example

Move all versions and merge into an existing folder:

```bash
python version-aware-cleanup.py \
  --operation move \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/old_data \
  --dest-prefix ftp_fgc_xqtl/merged_data \
  --merge
```

### Delete All Versions Example

Delete all versions under a given prefix:

```bash
python version-aware-cleanup.py \
  --operation delete \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/temp_data
```

## Pattern Matching

The tool supports filtering files by name patterns, allowing you to operate on specific files within a prefix:

### Pattern Matching Options

- `--pattern`: A pattern to filter files by name (supports glob patterns by default)
- `--pattern-type`: Type of pattern matching to use:
  - `glob`: Unix-style wildcard matching (default)
  - `regex`: Regular expression matching
  - `exact`: Exact filename matching

### Pattern Matching Behavior

1. Patterns are applied to filenames only (not to full paths)
2. Pattern matching is only applied to files, not folder markers
3. When using patterns with delete operations, you'll be asked for confirmation

### Examples

- Copy only `.bam` files from a folder:

```bash
python s3-version-ops.py \
  --operation copy \
  --source-bucket statfungen \
  --source-prefix ftp_fgc_xqtl/ROSMAP/test_bams \
  --dest-prefix ftp_fgc_xqtl/resource/toy_bam_data/rnaseq_bam \
  --pattern "*.bam"
```

## Notes
- The move operation performs a full versioned copy followed by deletion of all versions in the source.
- The delete operation permanently deletes all versions under the given prefix. This cannot be undone.
- This script is designed for versioned buckets. For non-versioned buckets, simpler aws s3 cp/mv/rm commands may suffice.
- For large datasets or prefixes containing millions of versions, consider running with additional logging and batching strategies.
- In S3, "folders" are just logical prefixes, but the script will create an empty object with a trailing slash to represent folders when needed.
