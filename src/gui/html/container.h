// litehtml drawing through QPainter, for the HTML reader (HtmlView). Nothing here reaches the network: the only
// pictures are the data: URIs the engine's sanitizer left in the document (approved raster bytes).
#pragma once
#include <litehtml.h>
#include <QFont>
#include <QHash>
#include <QImage>
#include <QPainter>
#include <QString>
#include <functional>
#include <vector>

// One word (or run of text) as litehtml drew it, in page coordinates: what selection and copy work on
struct TextRun {
    QString text;
    QRect rect;
    const QFont* font;
};

class HtmlContainer : public litehtml::document_container {
public:
    HtmlContainer() = default;
    void setPainter(QPainter* p) { m_painter = p; }
    // Recording: a draw with no painter only collects the text runs, in drawing order
    void startRecording(std::vector<TextRun>* runs) { m_runs = runs; }
    void stopRecording() { m_runs = nullptr; }
    // A picture of the page (data: URI), null if there is none
    QImage imageFor(const QString& src) { const QImage* i = image(src.toUtf8().constData()); return i ? *i : QImage(); }
    void setViewport(int width, int height) { m_width = width; m_height = height; }
    void setDefaultFont(const QString& family, int size) { m_family = family; m_familyUtf8 = family.toUtf8(); m_size = size; }
    std::function<void(const QString&)> onAnchor;
    std::function<void(const QString&)> onCursor;

    litehtml::uint_ptr create_font(const char* faceName, int size, int weight, litehtml::font_style italic,
                                   unsigned int decoration, litehtml::font_metrics* fm) override;
    void delete_font(litehtml::uint_ptr hFont) override;
    int text_width(const char* text, litehtml::uint_ptr hFont) override;
    void draw_text(litehtml::uint_ptr hdc, const char* text, litehtml::uint_ptr hFont, litehtml::web_color color,
                   const litehtml::position& pos) override;
    int pt_to_px(int pt) const override { return pt * 96 / 72; }
    int get_default_font_size() const override { return m_size; }
    const char* get_default_font_name() const override { return m_familyUtf8.constData(); }
    void draw_list_marker(litehtml::uint_ptr hdc, const litehtml::list_marker& marker) override;
    void load_image(const char* src, const char* baseurl, bool redraw_on_ready) override;
    void get_image_size(const char* src, const char* baseurl, litehtml::size& sz) override;
    void draw_background(litehtml::uint_ptr hdc, const std::vector<litehtml::background_paint>& bg) override;
    void draw_borders(litehtml::uint_ptr hdc, const litehtml::borders& borders, const litehtml::position& draw_pos,
                      bool root) override;
    void set_caption(const char*) override {}
    void set_base_url(const char*) override {}
    void link(const std::shared_ptr<litehtml::document>&, const litehtml::element::ptr&) override {}
    void on_anchor_click(const char* url, const litehtml::element::ptr&) override;
    void set_cursor(const char* cursor) override;
    void transform_text(litehtml::string& text, litehtml::text_transform tt) override;
    // No external style sheet is ever fetched
    void import_css(litehtml::string&, const litehtml::string&, litehtml::string&) override {}
    void set_clip(const litehtml::position& pos, const litehtml::border_radiuses&) override { m_clips.push_back(pos); }
    void del_clip() override { if (!m_clips.empty()) m_clips.pop_back(); }
    void get_client_rect(litehtml::position& client) const override { client = {0, 0, m_width, m_height}; }
    litehtml::element::ptr create_element(const char*, const litehtml::string_map&,
                                          const std::shared_ptr<litehtml::document>&) override { return nullptr; }
    void get_media_features(litehtml::media_features& media) const override;
    void get_language(litehtml::string& language, litehtml::string& culture) const override;

private:
    void clip();
    const QImage* image(const char* src);
    int m_width = 600;
    int m_height = 600;
    QString m_family = QStringLiteral("sans-serif");
    QByteArray m_familyUtf8 = m_family.toUtf8();
    int m_size = 15;
    QPainter* m_painter = nullptr;
    QHash<QString, QImage> m_images;
    std::vector<litehtml::position> m_clips;
    std::vector<TextRun>* m_runs = nullptr;
};
