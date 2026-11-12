#include "htmlview.h"
#include <QClipboard>
#include <QCursor>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QPainter>
#include <QStyleHints>
#include <QtMath>
#include <QtQml/qqml.h>

HtmlView::HtmlView(QQuickItem* parent) : QQuickPaintedItem(parent), m_container(std::make_unique<HtmlContainer>()) {
    setAcceptHoverEvents(true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton);
    setOpaquePainting(false);
    m_container->onAnchor = [this](const QString& url) { emit linkActivated(url); };
    m_container->onCursor = [this](const QString& cursor) {
        setCursor(cursor == QLatin1String("pointer") ? Qt::PointingHandCursor : Qt::IBeamCursor);
    };
    setCursor(Qt::IBeamCursor);
}

// The document holds fonts made by the container, and the runs point at them: they go first
HtmlView::~HtmlView() {
    m_runs.clear();
    m_doc.reset();
}

void HtmlView::setHtml(const QString& html) {
    if (html == m_html)
        return;
    m_html = html;
    emit htmlChanged();
    rebuild();
}

void HtmlView::setFontFamily(const QString& family) {
    if (family == m_family)
        return;
    m_family = family;
    emit fontChanged();
    rebuild();
}

void HtmlView::setFontSize(int size) {
    if (size == m_size)
        return;
    m_size = size;
    emit fontChanged();
    rebuild();
}

void HtmlView::setViewportY(qreal y) {
    if (qFuzzyCompare(y, m_viewportY))
        return;
    m_viewportY = y;
    emit viewportYChanged();
    update();
}

// A new page: parse it again (fonts and pictures belong to the document)
void HtmlView::rebuild() {
    m_runs.clear();
    m_doc.reset();
    m_laidOutWidth = 0;
    clearSelection();
    m_container->setDefaultFont(m_family, m_size);
    if (!m_html.isEmpty()) {
        m_container->setViewport(qMax(1, int(width())), qMax(1, int(height())));
        const QByteArray utf8 = m_html.toUtf8();
        m_doc = litehtml::document::createFromString(utf8.constData(), m_container.get());
    }
    relayout();
}

// A page wider than the item (a fixed 600 px table, a button with a min-width) is laid out at its own width and
// shrunk to fit, like a phone's mail reader, rather than cut on the right
void HtmlView::relayout() {
    const int w = int(width());
    int h = 0;
    m_scale = 1;
    if (m_doc && w > 0) {
        m_container->setViewport(w, qMax(1, int(height())));
        m_doc->render(w);
        const int needed = qMin(m_doc->content_width(), 4 * w);
        if (needed > w) {
            m_doc->render(needed);
            m_scale = qreal(w) / qMax(needed, m_doc->content_width());
        }
        m_laidOutWidth = w;
        h = qCeil(m_doc->content_height() * m_scale);
    }
    recordRuns();
    if (h != m_contentHeight) {
        m_contentHeight = h;
        emit contentHeightChanged();
    }
    update();
}

// The words as litehtml places them, for selection and copy (a new layout keeps the runs in the same order, so a
// selection survives a resize)
void HtmlView::recordRuns() {
    m_runs.clear();
    if (!m_doc)
        return;
    m_container->startRecording(&m_runs);
    const litehtml::position all(0, 0, qMax(1, m_doc->content_width()), qMax(1, m_doc->content_height()));
    m_doc->draw(0, 0, 0, &all);
    m_container->stopRecording();
    for (auto& run : m_runs)
        if (run.rect.width() <= 0)
            run.rect.setWidth(QFontMetrics(*run.font).horizontalAdvance(run.text));
    const int last = int(m_runs.size());
    auto clamp = [last](Caret& c) {
        if (c.run >= last)
            c = {0, 0};
    };
    clamp(m_anchor);
    clamp(m_cursor);
}

void HtmlView::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) {
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (int(newGeometry.width()) != m_laidOutWidth)
        relayout();
}

void HtmlView::paint(QPainter* painter) {
    if (!m_doc)
        return;
    painter->setRenderHint(QPainter::TextAntialiasing);
    painter->scale(m_scale, m_scale);
    const int top = int(m_viewportY / m_scale);
    painter->translate(0, -top);
    m_container->setPainter(painter);
    const litehtml::position clip(0, top, qCeil(width() / m_scale), qCeil(height() / m_scale));
    m_doc->draw(reinterpret_cast<litehtml::uint_ptr>(painter), 0, 0, &clip);
    m_container->setPainter(nullptr);

    // The selection, over the text; a gap between two selected words on one line is filled too
    if (!hasSelection())
        return;
    const Caret from = qMin(m_anchor, m_cursor), to = qMax(m_anchor, m_cursor);
    const QRect visible(clip.x, clip.y, clip.width, clip.height);
    for (int i = from.run; i <= to.run && i < int(m_runs.size()); ++i) {
        const TextRun& run = m_runs[i];
        if (!run.rect.intersects(visible))
            continue;
        const QFontMetrics m(*run.font);
        const int start = i == from.run ? from.offset : 0;
        const int end = i == to.run ? to.offset : int(run.text.size());
        int left = run.rect.x() + m.horizontalAdvance(run.text.left(start));
        int right = run.rect.x() + m.horizontalAdvance(run.text.left(end));
        if (i < to.run && end == run.text.size() && i + 1 < int(m_runs.size())) {
            const QRect& next = m_runs[i + 1].rect;
            // A word space, not the gap between two table cells
            if (next.top() < run.rect.bottom() && next.bottom() > run.rect.top() && next.left() > right
                && next.left() - right <= run.rect.height())
                right = next.left();
        }
        if (right > left)
            painter->fillRect(QRect(left, run.rect.y(), right - left, run.rect.height()), m_selectionColor);
    }
}

QPoint HtmlView::pagePoint(const QPointF& item) const {
    return QPoint(int(item.x() / m_scale), int((item.y() + m_viewportY) / m_scale));
}

// The character of a run at page x (rounded to the nearest gap)
int HtmlView::offsetIn(const TextRun& run, int x) const {
    if (x <= run.rect.left())
        return 0;
    const QFontMetrics m(*run.font);
    int previous = 0;
    for (int i = 1; i <= run.text.size(); ++i) {
        const int edge = m.horizontalAdvance(run.text.left(i));
        if (run.rect.x() + (previous + edge) / 2 >= x)
            return i - 1;
        previous = edge;
    }
    return int(run.text.size());
}

// The text place nearest a page point: the run on that line closest in x, else the closest line
HtmlView::Caret HtmlView::caretAt(const QPoint& p) const {
    int best = -1;
    qint64 bestScore = 0;
    for (int i = 0; i < int(m_runs.size()); ++i) {
        const QRect& r = m_runs[i].rect;
        const qint64 dy = p.y() < r.top() ? r.top() - p.y() : p.y() > r.bottom() ? p.y() - r.bottom() : 0;
        const qint64 dx = p.x() < r.left() ? r.left() - p.x() : p.x() > r.right() ? p.x() - r.right() : 0;
        const qint64 score = dy * 100000 + dx;
        if (best < 0 || score < bestScore) {
            best = i;
            bestScore = score;
        }
    }
    if (best < 0)
        return {};
    return {best, offsetIn(m_runs[best], p.x())};
}

QString HtmlView::selectedText() const {
    if (!hasSelection())
        return {};
    const Caret from = qMin(m_anchor, m_cursor), to = qMax(m_anchor, m_cursor);
    QString out;
    for (int i = from.run; i <= to.run && i < int(m_runs.size()); ++i) {
        const TextRun& run = m_runs[i];
        if (i > from.run) {
            // Same line: a space where litehtml left a gap; another line: a line break, two after a wide gap
            const QRect& prev = m_runs[i - 1].rect;
            if (run.rect.top() < prev.bottom() && run.rect.bottom() > prev.top()) {
                if (run.rect.left() > prev.right() + 1 && !out.endsWith(' '))
                    out += ' ';
            } else {
                out += run.rect.top() - prev.bottom() > prev.height() ? QStringLiteral("\n\n") : QStringLiteral("\n");
            }
        }
        const int start = i == from.run ? from.offset : 0;
        const int end = i == to.run ? to.offset : int(run.text.size());
        out += run.text.mid(start, end - start);
    }
    return out;
}

bool HtmlView::copy() const {
    const QString text = selectedText();
    if (text.isEmpty())
        return false;
    QGuiApplication::clipboard()->setText(text);
    return true;
}

void HtmlView::selectAll() {
    if (m_runs.empty())
        return;
    m_anchor = {0, 0};
    m_cursor = {int(m_runs.size()) - 1, int(m_runs.back().text.size())};
    emit selectionChanged();
    update();
}

void HtmlView::clearSelection() {
    if (!hasSelection())
        return;
    m_anchor = m_cursor = {};
    emit selectionChanged();
    update();
}

void HtmlView::copyText(const QString& text) const { QGuiApplication::clipboard()->setText(text); }

bool HtmlView::copyImage() const {
    const QImage image = m_container->imageFor(m_contextImage);
    if (image.isNull())
        return false;
    QGuiApplication::clipboard()->setImage(image);
    return true;
}

// The link under the pointer, for the address shown at the bottom of the reader
void HtmlView::updateHovered() {
    QString link;
    if (m_doc) {
        for (auto el = std::const_pointer_cast<litehtml::element>(m_doc->get_over_element()); el; el = el->parent()) {
            if (const char* href = el->get_attr("href")) {
                link = QString::fromUtf8(href);
                break;
            }
        }
    }
    if (link != m_hovered) {
        m_hovered = link;
        emit hoveredLinkChanged();
    }
}

// The picture under the pointer (an <img> with a data: source), empty if none
QString HtmlView::imageUnder() const {
    auto el = m_doc ? m_doc->get_over_element() : nullptr;
    if (el && qstrcmp(el->get_tagName(), "img") == 0)
        if (const char* src = el->get_attr("src"))
            if (!m_container->imageFor(QString::fromUtf8(src)).isNull())
                return QString::fromUtf8(src);
    return {};
}

void HtmlView::hover(const QPoint& p) {
    if (!m_doc)
        return;
    litehtml::position::vector boxes;
    if (m_doc->on_mouse_over(p.x(), p.y(), p.x(), p.y(), boxes))
        update();
    updateHovered();
}

void HtmlView::hoverMoveEvent(QHoverEvent* event) { hover(pagePoint(event->position())); }

void HtmlView::hoverLeaveEvent(QHoverEvent*) {
    if (!m_doc)
        return;
    litehtml::position::vector boxes;
    if (m_doc->on_mouse_leave(boxes))
        update();
    setCursor(Qt::IBeamCursor);
    updateHovered();
}

void HtmlView::mousePressEvent(QMouseEvent* event) {
    if (!m_doc) {
        event->ignore();
        return;
    }
    const QPoint p = pagePoint(event->position());
    hover(p);
    if (event->button() == Qt::RightButton) {
        m_contextImage = imageUnder();
        emit contextMenuRequested(event->position().x(), event->position().y(), m_hovered, !m_contextImage.isEmpty());
        return;
    }
    // A press starts a selection (Shift extends the current one); on a link, a release without a drag opens it
    forceActiveFocus(Qt::MouseFocusReason);
    m_pressed = true;
    m_dragged = false;
    m_pressAt = event->position();
    const Caret at = caretAt(p);
    if (!(event->modifiers() & Qt::ShiftModifier))
        m_anchor = at;
    const bool had = hasSelection();
    m_cursor = at;
    if (had || hasSelection()) {
        emit selectionChanged();
        update();
    }
}

void HtmlView::mouseMoveEvent(QMouseEvent* event) {
    if (!m_pressed)
        return;
    if (!m_dragged && (event->position() - m_pressAt).manhattanLength() < QGuiApplication::styleHints()->startDragDistance())
        return;
    // The drag is a selection: the Flickable around must not take it for a scroll
    m_dragged = true;
    setKeepMouseGrab(true);
    const Caret at = caretAt(pagePoint(event->position()));
    if (!(at == m_cursor)) {
        m_cursor = at;
        emit selectionChanged();
        update();
    }
}

void HtmlView::mouseReleaseEvent(QMouseEvent* event) {
    if (!m_pressed)
        return;
    m_pressed = false;
    setKeepMouseGrab(false);
    if (!m_dragged && !m_hovered.isEmpty() && event->button() == Qt::LeftButton && !hasSelection())
        emit linkActivated(m_hovered);
}

// Double click: the word under the pointer
void HtmlView::mouseDoubleClickEvent(QMouseEvent* event) {
    if (!m_doc || event->button() != Qt::LeftButton || m_runs.empty())
        return;
    const Caret at = caretAt(pagePoint(event->position()));
    const QString& text = m_runs[at.run].text;
    auto word = [](QChar c) { return c.isLetterOrNumber() || c == '_' || c == '-' || c == '\''; };
    int start = qMin(at.offset, int(text.size()));
    int end = start;
    while (start > 0 && word(text[start - 1]))
        --start;
    while (end < text.size() && word(text[end]))
        ++end;
    if (start == end)
        end = qMin(int(text.size()), start + 1);
    m_anchor = {at.run, start};
    m_cursor = {at.run, end};
    m_pressed = false;
    emit selectionChanged();
    update();
}

extern "C" void fili_register_html_view() { qmlRegisterType<HtmlView>("Fili.Html", 1, 0, "HtmlView"); }
