// HtmlView (QML: import Fili.Html; HtmlView {}): an HTML mail laid out by litehtml and painted with QPainter.
// The item is as wide as the page and only as tall as the visible slice: `contentHeight` is the page's height and
// `viewportY` the page row drawn at its top, so a long mail never needs a texture taller than the window.
// Text is selectable with the mouse (drag, double click for a word) and copied with copy(); a right click sends
// contextMenuRequested with the link and the picture under the pointer, for the reader's menu.
#pragma once
#include "container.h"
#include <QQuickPaintedItem>
#include <memory>
#include <vector>

namespace litehtml { class document; }

class HtmlView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString html READ html WRITE setHtml NOTIFY htmlChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontChanged)
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY fontChanged)
    Q_PROPERTY(int contentHeight READ contentHeight NOTIFY contentHeightChanged)
    Q_PROPERTY(qreal viewportY READ viewportY WRITE setViewportY NOTIFY viewportYChanged)
    Q_PROPERTY(QString hoveredLink READ hoveredLink NOTIFY hoveredLinkChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(QColor selectionColor MEMBER m_selectionColor)

public:
    explicit HtmlView(QQuickItem* parent = nullptr);
    ~HtmlView() override;

    QString html() const { return m_html; }
    void setHtml(const QString& html);
    QString fontFamily() const { return m_family; }
    void setFontFamily(const QString& family);
    int fontSize() const { return m_size; }
    void setFontSize(int size);
    int contentHeight() const { return m_contentHeight; }
    qreal viewportY() const { return m_viewportY; }
    void setViewportY(qreal y);
    QString hoveredLink() const { return m_hovered; }
    bool hasSelection() const { return !(m_anchor == m_cursor); }

    void paint(QPainter* painter) override;

    Q_INVOKABLE QString selectedText() const;
    // Copy the selection to the clipboard (false: nothing selected)
    Q_INVOKABLE bool copy() const;
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    // Clipboard helpers for the context menu: a text (a link address) or the picture under the last right click
    Q_INVOKABLE void copyText(const QString& text) const;
    Q_INVOKABLE bool copyImage() const;

signals:
    void htmlChanged();
    void fontChanged();
    void contentHeightChanged();
    void viewportYChanged();
    void hoveredLinkChanged();
    void selectionChanged();
    // A link was clicked: the reader decides what to do with it (open it in the browser)
    void linkActivated(const QString& url);
    // Right click at (x, y) in the item: the link and whether a picture is under it
    void contextMenuRequested(qreal x, qreal y, const QString& link, bool image);

protected:
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;
    void hoverMoveEvent(QHoverEvent* event) override;
    void hoverLeaveEvent(QHoverEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;
    void mouseDoubleClickEvent(QMouseEvent* event) override;

private:
    // A place in the text: run index and character offset in it
    struct Caret {
        int run = 0;
        int offset = 0;
        bool operator==(const Caret& o) const { return run == o.run && offset == o.offset; }
        bool operator<(const Caret& o) const { return run < o.run || (run == o.run && offset < o.offset); }
    };
    void rebuild();
    void relayout();
    void recordRuns();
    void updateHovered();
    QPoint pagePoint(const QPointF& item) const;
    Caret caretAt(const QPoint& page) const;
    int offsetIn(const TextRun& run, int x) const;
    void hover(const QPoint& page);
    QString imageUnder() const;
    std::unique_ptr<HtmlContainer> m_container;
    std::shared_ptr<litehtml::document> m_doc;
    std::vector<TextRun> m_runs;
    QString m_html;
    QString m_family = QStringLiteral("sans-serif");
    int m_size = 15;
    int m_laidOutWidth = 0;
    int m_contentHeight = 0;
    qreal m_viewportY = 0;
    qreal m_scale = 1;
    QString m_hovered;
    Caret m_anchor, m_cursor;
    QPointF m_pressAt;
    bool m_pressed = false;
    bool m_dragged = false;
    QString m_contextImage;
    QColor m_selectionColor = QColor(64, 128, 255, 90);
};

// Registers HtmlView as `Fili.Html 1.0` (called from Rust before the QML engine loads)
extern "C" void fili_register_html_view();
