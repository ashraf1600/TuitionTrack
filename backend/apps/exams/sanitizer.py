"""
HTML Sanitization Utility

Uses nh3 (Python Ammonia bindings) to sanitize HTML content from the
TipTap rich-text editor before storing in the database.

Defence-in-depth strategy:
1. Frontend: DOMPurify (client-side, first pass)
2. Backend: nh3 sanitizer (server-side, authoritative pass — this module)
3. Frontend render: DOMPurify again when rendering to students

The whitelist is designed to:
- Allow all common rich-text formatting tags
- Allow tables (important for science/math exam questions)
- Allow images (for diagrams embedded in exams)
- Preserve KaTeX/LaTeX math containers (class="math-inline", class="math-block")
- Strip ALL script tags, event handlers, and javascript: URIs
"""
import nh3

# ── Allowed HTML Tags ──────────────────────────────────────────────────────────
ALLOWED_TAGS = {
    # Text formatting
    'p', 'br', 'span', 'div',
    'strong', 'b', 'em', 'i', 'u', 's', 'mark', 'sub', 'sup',
    # Headings
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    # Structural
    'blockquote', 'hr',
    # Code
    'code', 'pre', 'kbd',
    # Lists
    'ul', 'ol', 'li',
    # Tables (critical for exam question formatting)
    'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'caption',
    # Media
    'img', 'figure', 'figcaption',
    # Links (allowed but restricted to safe schemes)
    'a',
}

# ── Allowed HTML Attributes Per Tag ───────────────────────────────────────────
ALLOWED_ATTRIBUTES = {
    # Global attributes (on any tag)
    '*': {'class', 'id', 'style'},
    # Images — only safe src schemes will survive nh3's URL cleaning
    'img': {'src', 'alt', 'width', 'height', 'title'},
    # Links — restricted href schemes
    'a': {'href', 'title', 'target'},
    # Table layout
    'th': {'colspan', 'rowspan', 'scope'},
    'td': {'colspan', 'rowspan'},
    'table': {'border', 'cellpadding', 'cellspacing'},
    # TipTap data attributes for math blocks
    'span': {'class', 'data-type', 'data-latex'},
    'div': {'class', 'data-type', 'data-latex'},
}


def sanitize_exam_html(raw_html: str) -> str:
    """
    Sanitize raw HTML from the TipTap editor.

    - Strips all script tags, event handlers (onclick, onload, onerror etc.)
    - Strips javascript:, data:text/html, and vbscript: URI schemes
    - Preserves safe formatting, tables, and KaTeX math containers
    - Preserves safe image src attributes (http/https only)

    Args:
        raw_html: Raw HTML string from the frontend editor

    Returns:
        Sanitized HTML safe for database storage and frontend rendering
    """
    if not raw_html or not raw_html.strip():
        return ''

    sanitized = nh3.clean(
        raw_html,
        tags=ALLOWED_TAGS,
        attributes=ALLOWED_ATTRIBUTES,
        # Strip dangerous link schemes (javascript:, data:, vbscript:)
        url_schemes={'http', 'https', 'mailto'},
        link_rel='noopener noreferrer',
        # Strips HTML comments (can be used to hide XSS payloads)
        strip_comments=True,
    )
    return sanitized
