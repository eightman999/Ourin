#!/usr/bin/env python3
"""
Generate bilingual HTML documentation from markdown files
Supports language switching between EN and JA versions
"""
import os
import re
from pathlib import Path
from datetime import datetime

try:
    import markdown
    from markdown.extensions.codehilite import CodeHiliteExtension
    from markdown.extensions.fenced_code import FencedCodeExtension
    from markdown.extensions.tables import TableExtension
    from markdown.extensions.toc import TocExtension
except ImportError:
    print("Error: markdown package not installed")
    print("Install with: pip3 install markdown")
    exit(1)

DOCS_DIR = Path(__file__).parent
HTML_DIR = DOCS_DIR / "html"

# CSS template for HTML output
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", "Hiragino Kaku Gothic ProN", "Hiragino Sans", "游ゴシック", YuGothic, "メイリオ", Meiryo, sans-serif;
            line-height: 1.6;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        .content {{
            background-color: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .lang-switcher {{
            text-align: right;
            margin-bottom: 20px;
            padding: 10px;
            background-color: #f0f0f0;
            border-radius: 5px;
        }}
        .lang-switcher a {{
            margin: 0 5px;
            padding: 5px 15px;
            background-color: white;
            border: 1px solid #ddd;
            border-radius: 3px;
            text-decoration: none;
            color: #333;
        }}
        .lang-switcher a:hover {{
            background-color: #e0e0e0;
        }}
        .lang-switcher a.active {{
            background-color: #0066cc;
            color: white;
            border-color: #0066cc;
        }}
        h1 {{
            border-bottom: 3px solid #333;
            padding-bottom: 10px;
            color: #333;
        }}
        h2 {{
            border-bottom: 2px solid #666;
            padding-bottom: 8px;
            margin-top: 30px;
            color: #444;
        }}
        h3 {{
            margin-top: 25px;
            color: #555;
        }}
        code {{
            background-color: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: "SF Mono", "Menlo", "Monaco", "Courier New", monospace;
            font-size: 0.9em;
        }}
        pre {{
            background-color: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid #333;
        }}
        pre code {{
            background-color: transparent;
            padding: 0;
        }}
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
        }}
        th, td {{
            border: 1px solid #ddd;
            padding: 12px;
            text-align: left;
        }}
        th {{
            background-color: #f8f8f8;
            font-weight: bold;
        }}
        tr:nth-child(even) {{
            background-color: #f9f9f9;
        }}
        a {{
            color: #0066cc;
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        blockquote {{
            border-left: 4px solid #ddd;
            padding-left: 20px;
            margin-left: 0;
            color: #666;
            font-style: italic;
        }}
        ul, ol {{
            padding-left: 30px;
        }}
        li {{
            margin: 8px 0;
        }}
        hr {{
            border: none;
            border-top: 2px solid #ddd;
            margin: 30px 0;
        }}
        .footer {{
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }}
        .back-link {{
            display: inline-block;
            margin-bottom: 20px;
            color: #0066cc;
            text-decoration: none;
        }}
        .back-link:hover {{
            text-decoration: underline;
        }}
    </style>
</head>
<body>
    <div class="content">
        <div class="lang-switcher">
            {lang_switcher}
        </div>
        <div class="back-link">
            <a href="index.html">← {back_text}</a>
        </div>
        {body}
        <div class="footer">
            <p>Generated: {date} | <a href="../README_ja-jp.md">Source (MD)</a></p>
        </div>
    </div>
</body>
</html>
"""

def get_title_from_md(content):
    """Extract first heading as title"""
    for line in content.split('\n'):
        if line.strip().startswith('#'):
            title = re.sub(r'^#+\s*', '', line.strip())
            return title
    return "Ourin Documentation"

def get_language_code(filename):
    """Extract language code from filename"""
    if filename.endswith('_ja-jp.md'):
        return 'ja', 'ja-jp'
    elif filename.endswith('_en-us.md'):
        return 'en', 'en-us'
    return 'ja', 'unknown'

def get_base_name(filename):
    """Get base name without language suffix"""
    if filename.endswith('_ja-jp.md'):
        return filename[:-10]
    elif filename.endswith('_en-us.md'):
        return filename[:-10]
    return filename[:-3]

def generate_lang_switcher(base_name, current_lang, has_ja, has_en):
    """Generate language switcher HTML"""
    switcher_parts = []
    
    if has_ja:
        ja_class = 'active' if current_lang == 'ja-jp' else ''
        switcher_parts.append(f'<a href="{base_name}_ja-jp.html" class="{ja_class}">日本語</a>')
    
    if has_en:
        en_class = 'active' if current_lang == 'en-us' else ''
        switcher_parts.append(f'<a href="{base_name}_en-us.html" class="{en_class}">English</a>')
    
    return ' | '.join(switcher_parts) if switcher_parts else ''

def convert_md_to_html(md_file, output_dir):
    """Convert a markdown file to HTML with language support"""
    try:
        with open(md_file, 'r', encoding='utf-8') as f:
            md_content = f.read()
        
        # Get language info
        filename = md_file.name
        lang_code, lang_suffix = get_language_code(filename)
        base_name = get_base_name(filename)
        
        # Check if other language version exists
        has_ja = (md_file.parent / f"{base_name}_ja-jp.md").exists()
        has_en = (md_file.parent / f"{base_name}_en-us.md").exists()
        
        # Extract title
        title = get_title_from_md(md_content)
        
        # Configure markdown processor
        md = markdown.Markdown(extensions=[
            'extra',
            'codehilite',
            'fenced_code',
            'tables',
            TocExtension(title='目次' if lang_code == 'ja' else 'Contents')
        ])
        
        # Convert markdown to HTML
        html_body = md.convert(md_content)
        
        # Generate language switcher
        lang_switcher = generate_lang_switcher(base_name, lang_suffix, has_ja, has_en)
        
        # Back link text
        back_text = "目次に戻る" if lang_code == 'ja' else "Back to Index"
        
        # Create full HTML
        html = HTML_TEMPLATE.format(
            lang=lang_code,
            title=title,
            lang_switcher=lang_switcher,
            back_text=back_text,
            body=html_body,
            date=datetime.now().strftime('%Y-%m-%d')
        )
        
        # Write output
        output_file = output_dir / f"{base_name}_{lang_suffix}.html"
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(html)
        
        return True, str(output_file.name)
    
    except Exception as e:
        return False, str(e)

def main():
    """Main conversion process"""
    print("=" * 70)
    print("Ourin Documentation HTML Generator")
    print("=" * 70)
    print()
    
    # Create output directory
    HTML_DIR.mkdir(exist_ok=True)
    
    # Find all markdown files
    md_files = sorted(DOCS_DIR.glob("*.md"))
    
    # Exclude special files
    exclude_files = {'TRANSLATION_MANIFEST.md', 'TRANSLATION_WORKFLOW.md'}
    md_files = [f for f in md_files if f.name not in exclude_files]
    
    success_count = 0
    failed_count = 0
    failed_files = []
    
    print(f"Processing {len(md_files)} markdown files...\n")
    
    for md_file in md_files:
        success, result = convert_md_to_html(md_file, HTML_DIR)
        
        if success:
            print(f"✓ {md_file.name} → {result}")
            success_count += 1
        else:
            print(f"✗ {md_file.name}: {result}")
            failed_count += 1
            failed_files.append((md_file.name, result))
    
    print()
    print("=" * 70)
    print(f"Conversion Complete: {success_count} succeeded, {failed_count} failed")
    print("=" * 70)
    
    if failed_files:
        print("\nFailed files:")
        for fname, error in failed_files:
            print(f"  - {fname}: {error}")
    
    print(f"\nHTML files generated in: {HTML_DIR}")
    print("\nNext steps:")
    print("  1. Update index.html for bilingual navigation")
    print("  2. Review generated HTML files")
    print("  3. Test language switching functionality")

if __name__ == '__main__':
    main()
