#!/usr/bin/env python3
"""
PDF text extraction using PyMuPDF (fitz).
Usage:
  pdf_extract.py <path> [--pages START-END] [--metadata] [--format text|markdown]

Outputs extracted text to stdout as UTF-8.
"""

import sys
import json
import argparse

try:
    import fitz  # PyMuPDF
except ImportError:
    print("Error: PyMuPDF not installed. Run: pip install pymupdf", file=sys.stderr)
    sys.exit(1)


def extract_text(path, pages=None, fmt="text"):
    doc = fitz.open(path)
    total_pages = len(doc)
    
    # Determine page range
    if pages:
        start, end = pages
        start = max(0, start - 1)  # Convert to 0-indexed
        end = min(total_pages, end)
        page_range = range(start, end)
    else:
        page_range = range(total_pages)
    
    output = []
    
    for i in page_range:
        page = doc[i]
        
        if fmt == "markdown":
            # Extract with basic structure preservation
            blocks = page.get_text("dict")["blocks"]
            page_text = []
            for block in blocks:
                if block["type"] == 0:  # Text block
                    for line in block.get("lines", []):
                        line_text = ""
                        for span in line.get("spans", []):
                            text = span["text"]
                            size = span.get("size", 12)
                            flags = span.get("flags", 0)
                            
                            # Bold
                            if flags & 2**4:
                                text = f"**{text}**"
                            # Italic
                            if flags & 2**1:
                                text = f"*{text}*"
                            # Large text = heading
                            if size > 16:
                                text = f"## {text}"
                            elif size > 14:
                                text = f"### {text}"
                            
                            line_text += text
                        page_text.append(line_text)
                elif block["type"] == 1:  # Image block
                    page_text.append("[Image]")
            
            output.append(f"\n--- Page {i + 1} ---\n")
            output.append("\n".join(page_text))
        else:
            text = page.get_text("text")
            output.append(f"\n--- Page {i + 1} ---\n")
            output.append(text)
    
    doc.close()
    return "\n".join(output), total_pages


def extract_metadata(path):
    doc = fitz.open(path)
    meta = doc.metadata or {}
    info = {
        "title": meta.get("title", ""),
        "author": meta.get("author", ""),
        "subject": meta.get("subject", ""),
        "creator": meta.get("creator", ""),
        "producer": meta.get("producer", ""),
        "creation_date": meta.get("creationDate", ""),
        "mod_date": meta.get("modDate", ""),
        "total_pages": len(doc),
        "file_size_bytes": doc.stream_length if hasattr(doc, 'stream_length') else None,
    }
    
    # Page dimensions
    if len(doc) > 0:
        page = doc[0]
        rect = page.rect
        info["page_width"] = round(rect.width, 1)
        info["page_height"] = round(rect.height, 1)
    
    # Check for images
    image_count = 0
    for i in range(min(len(doc), 10)):  # Check first 10 pages
        image_count += len(doc[i].get_images())
    info["images_found"] = image_count
    
    # Check if text is extractable
    sample = doc[0].get_text("text").strip() if len(doc) > 0 else ""
    info["has_text"] = len(sample) > 10
    info["sample"] = sample[:200] if sample else "[No extractable text - may be scanned/image-based]"
    
    doc.close()
    return info


def extract_tables(path, page_num=None):
    """Extract tables from PDF pages."""
    doc = fitz.open(path)
    tables_output = []
    
    pages = [page_num - 1] if page_num else range(len(doc))
    
    for i in pages:
        if i >= len(doc):
            continue
        page = doc[i]
        tabs = page.find_tables()
        if tabs and tabs.tables:
            for t_idx, table in enumerate(tabs.tables):
                tables_output.append(f"\n--- Page {i + 1}, Table {t_idx + 1} ---")
                data = table.extract()
                if data:
                    # Format as markdown table
                    if data[0]:
                        headers = [str(h or "") for h in data[0]]
                        tables_output.append("| " + " | ".join(headers) + " |")
                        tables_output.append("| " + " | ".join(["---"] * len(headers)) + " |")
                    for row in data[1:]:
                        cells = [str(c or "") for c in row]
                        tables_output.append("| " + " | ".join(cells) + " |")
    
    doc.close()
    return "\n".join(tables_output) if tables_output else "No tables found."


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract text from PDFs using PyMuPDF")
    parser.add_argument("path", help="Path to PDF file")
    parser.add_argument("--pages", help="Page range (e.g., 1-5)", default=None)
    parser.add_argument("--metadata", action="store_true", help="Extract metadata only")
    parser.add_argument("--tables", action="store_true", help="Extract tables")
    parser.add_argument("--table-page", type=int, help="Extract tables from specific page", default=None)
    parser.add_argument("--format", choices=["text", "markdown"], default="text", help="Output format")
    
    args = parser.parse_args()
    
    try:
        if args.metadata:
            meta = extract_metadata(args.path)
            print(json.dumps(meta, indent=2, default=str))
        elif args.tables:
            result = extract_tables(args.path, args.table_page)
            print(result)
        else:
            pages = None
            if args.pages:
                parts = args.pages.split("-")
                pages = (int(parts[0]), int(parts[1]) if len(parts) > 1 else int(parts[0]))
            
            text, total = extract_text(args.path, pages, args.format)
            print(f"[PDF: {total} pages]\n{text}")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
