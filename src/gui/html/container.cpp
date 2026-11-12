#include "container.h"
#include <QFontDatabase>
#include <QFontMetrics>
#include <QPainterPath>

static QColor qc(const litehtml::web_color& c) { return QColor(c.red, c.green, c.blue, c.alpha); }

litehtml::uint_ptr HtmlContainer::create_font(const char* faceName, int size, int weight, litehtml::font_style italic,
                                              unsigned int decoration, litehtml::font_metrics* fm) {
    // The first installed family of the CSS list; generic and unknown names fall back to the reader's font
    QString chosen = m_family;
    static const QStringList families = QFontDatabase::families();
    for (QString f : QString::fromUtf8(faceName).split(',')) {
        f = f.trimmed().remove('"').remove('\'');
        if (f.compare("monospace", Qt::CaseInsensitive) == 0) {
            chosen = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
            break;
        }
        if (families.contains(f, Qt::CaseInsensitive)) {
            chosen = f;
            break;
        }
    }
    auto* font = new QFont(chosen);
    font->setPixelSize(qMax(1, size));
    font->setWeight(QFont::Weight(qBound(1, weight, 1000)));
    font->setItalic(italic == litehtml::font_style_italic);
    font->setUnderline(decoration & litehtml::font_decoration_underline);
    font->setStrikeOut(decoration & litehtml::font_decoration_linethrough);
    if (fm) {
        QFontMetrics m(*font);
        fm->ascent = m.ascent();
        fm->descent = m.descent();
        fm->height = m.height();
        fm->x_height = m.xHeight();
        fm->draw_spaces = font->underline() || font->strikeOut();
    }
    return reinterpret_cast<litehtml::uint_ptr>(font);
}

void HtmlContainer::delete_font(litehtml::uint_ptr hFont) { delete reinterpret_cast<QFont*>(hFont); }

int HtmlContainer::text_width(const char* text, litehtml::uint_ptr hFont) {
    return QFontMetrics(*reinterpret_cast<QFont*>(hFont)).horizontalAdvance(QString::fromUtf8(text));
}

void HtmlContainer::clip() {
    if (!m_clips.empty()) {
        const auto& c = m_clips.back();
        m_painter->setClipRect(c.x, c.y, c.width, c.height, Qt::IntersectClip);
    }
}

void HtmlContainer::draw_text(litehtml::uint_ptr, const char* text, litehtml::uint_ptr hFont, litehtml::web_color color,
                              const litehtml::position& pos) {
    if (m_runs) {
        m_runs->push_back({QString::fromUtf8(text), QRect(pos.x, pos.y, pos.width, pos.height), reinterpret_cast<QFont*>(hFont)});
        return;
    }
    if (!m_painter)
        return;
    m_painter->save();
    clip();
    const QFont& font = *reinterpret_cast<QFont*>(hFont);
    m_painter->setFont(font);
    m_painter->setPen(qc(color));
    m_painter->drawText(pos.x, pos.y + QFontMetrics(font).ascent(), QString::fromUtf8(text));
    m_painter->restore();
}

static QString alpha(int n, bool upper) {
    QString s;
    for (; n > 0; n = (n - 1) / 26)
        s.prepend(QChar((upper ? 'A' : 'a') + (n - 1) % 26));
    return s;
}

static QString roman(int n, bool upper) {
    static const std::pair<int, const char*> table[] = {{1000, "m"}, {900, "cm"}, {500, "d"}, {400, "cd"}, {100, "c"},
        {90, "xc"}, {50, "l"}, {40, "xl"}, {10, "x"}, {9, "ix"}, {5, "v"}, {4, "iv"}, {1, "i"}};
    QString s;
    for (const auto& [value, glyph] : table)
        for (; n >= value; n -= value)
            s += QString::fromLatin1(glyph);
    return upper ? s.toUpper() : s;
}

void HtmlContainer::draw_list_marker(litehtml::uint_ptr, const litehtml::list_marker& marker) {
    if (!m_painter)
        return;
    m_painter->save();
    clip();
    m_painter->setRenderHint(QPainter::Antialiasing);
    const QRectF r(marker.pos.x, marker.pos.y, marker.pos.width, marker.pos.height);
    QString label;
    switch (marker.marker_type) {
    case litehtml::list_style_type_none:
        break;
    case litehtml::list_style_type_circle:
        m_painter->setPen(qc(marker.color));
        m_painter->drawEllipse(r);
        break;
    case litehtml::list_style_type_square:
        m_painter->fillRect(r, qc(marker.color));
        break;
    case litehtml::list_style_type_disc:
        m_painter->setPen(Qt::NoPen);
        m_painter->setBrush(qc(marker.color));
        m_painter->drawEllipse(r);
        break;
    case litehtml::list_style_type_lower_alpha:
    case litehtml::list_style_type_lower_latin:
        label = alpha(marker.index, false);
        break;
    case litehtml::list_style_type_upper_alpha:
    case litehtml::list_style_type_upper_latin:
        label = alpha(marker.index, true);
        break;
    case litehtml::list_style_type_lower_roman:
        label = roman(marker.index, false);
        break;
    case litehtml::list_style_type_upper_roman:
        label = roman(marker.index, true);
        break;
    default:
        label = QString::number(marker.index);
    }
    if (!label.isEmpty() && marker.font) {
        // The numbers end just left of the item, like a browser's
        const QFont& font = *reinterpret_cast<QFont*>(marker.font);
        label += '.';
        m_painter->setFont(font);
        m_painter->setPen(qc(marker.color));
        const QFontMetrics m(font);
        const int right = marker.pos.x + marker.pos.width;
        m_painter->drawText(right - m.horizontalAdvance(label), marker.pos.y + marker.pos.height, label);
    }
    m_painter->restore();
}

// Pictures come as data: URIs only; anything else (http, cid, file) is left blank
const QImage* HtmlContainer::image(const char* src) {
    const QString key = QString::fromUtf8(src);
    auto it = m_images.find(key);
    if (it == m_images.end()) {
        QImage img;
        if (key.startsWith(QLatin1String("data:"), Qt::CaseInsensitive)) {
            const int comma = key.indexOf(',');
            if (comma > 0 && key.left(comma).contains(QLatin1String(";base64"), Qt::CaseInsensitive))
                img.loadFromData(QByteArray::fromBase64(key.mid(comma + 1).toLatin1()));
        }
        it = m_images.insert(key, img);
    }
    return it->isNull() ? nullptr : &*it;
}

void HtmlContainer::load_image(const char* src, const char*, bool) { image(src); }

void HtmlContainer::get_image_size(const char* src, const char*, litehtml::size& sz) {
    if (const QImage* img = image(src)) {
        sz.width = img->width();
        sz.height = img->height();
    } else {
        sz.width = sz.height = 0;
    }
}

void HtmlContainer::draw_background(litehtml::uint_ptr, const std::vector<litehtml::background_paint>& list) {
    if (list.empty() || !m_painter)
        return;
    m_painter->save();
    clip();
    const auto& last = list.back();
    const auto& b = last.border_box;
    const auto& rad = last.border_radius;
    m_painter->setRenderHint(QPainter::Antialiasing);
    if (rad.top_left_x > 0) {
        QPainterPath shape;
        shape.addRoundedRect(b.x, b.y, b.width, b.height, rad.top_left_x, rad.top_left_y);
        m_painter->setClipPath(shape, Qt::IntersectClip);
    }
    if (last.color.alpha)
        m_painter->fillRect(QRect(last.clip_box.x, last.clip_box.y, last.clip_box.width, last.clip_box.height), qc(last.color));
    // The pictures of <img> elements are drawn here too: litehtml paints them as backgrounds of their box
    for (auto it = list.rbegin(); it != list.rend(); ++it) {
        if (it->image.empty() || it->image_size.width == 0)
            continue;
        const QImage* img = image(it->image.c_str());
        if (!img)
            continue;
        const QRect target(it->position_x, it->position_y, it->image_size.width, it->image_size.height);
        m_painter->setRenderHint(QPainter::SmoothPixmapTransform);
        if (it->repeat == litehtml::background_repeat_no_repeat)
            m_painter->drawImage(target, *img);
        else
            m_painter->drawTiledPixmap(QRect(it->clip_box.x, it->clip_box.y, it->clip_box.width, it->clip_box.height),
                                       QPixmap::fromImage(img->scaled(target.size())), QPoint(target.x(), target.y()));
    }
    m_painter->restore();
}

void HtmlContainer::draw_borders(litehtml::uint_ptr, const litehtml::borders& bd, const litehtml::position& p, bool) {
    if (!m_painter)
        return;
    m_painter->save();
    clip();
    // Rounded corners (buttons made of a bordered table cell): one stroke along the rounded outline, when the
    // four sides look alike; otherwise the sides are drawn straight
    const auto& rad = bd.radius;
    const bool round = rad.top_left_x > 0 || rad.top_right_x > 0 || rad.bottom_left_x > 0 || rad.bottom_right_x > 0;
    const bool uniform = bd.top.width > 0 && bd.top.width == bd.bottom.width && bd.top.width == bd.left.width
        && bd.top.width == bd.right.width && bd.top.style == litehtml::border_style_solid
        && bd.top.style == bd.bottom.style && bd.top.style == bd.left.style && bd.top.style == bd.right.style
        && qc(bd.top.color) == qc(bd.bottom.color) && qc(bd.top.color) == qc(bd.left.color) && qc(bd.top.color) == qc(bd.right.color);
    if (round && uniform) {
        const qreal w = bd.top.width, h = w / 2;
        m_painter->setRenderHint(QPainter::Antialiasing);
        m_painter->setPen(QPen(qc(bd.top.color), w));
        m_painter->setBrush(Qt::NoBrush);
        m_painter->drawRoundedRect(QRectF(p.x + h, p.y + h, p.width - w, p.height - w), qMax(0.0, rad.top_left_x - h),
                                   qMax(0.0, rad.top_left_y - h));
        m_painter->restore();
        return;
    }
    auto side = [&](const litehtml::border& b, QLine line) {
        if (b.width <= 0 || b.style == litehtml::border_style_none || b.style == litehtml::border_style_hidden)
            return;
        QPen pen(qc(b.color), b.width);
        pen.setCapStyle(Qt::FlatCap);
        if (b.style == litehtml::border_style_dotted) pen.setStyle(Qt::DotLine);
        if (b.style == litehtml::border_style_dashed) pen.setStyle(Qt::DashLine);
        m_painter->setPen(pen);
        m_painter->drawLine(line);
    };
    side(bd.top, QLine(p.x, p.y + bd.top.width / 2, p.x + p.width, p.y + bd.top.width / 2));
    side(bd.bottom, QLine(p.x, p.y + p.height - (bd.bottom.width + 1) / 2, p.x + p.width, p.y + p.height - (bd.bottom.width + 1) / 2));
    side(bd.left, QLine(p.x + bd.left.width / 2, p.y, p.x + bd.left.width / 2, p.y + p.height));
    side(bd.right, QLine(p.x + p.width - (bd.right.width + 1) / 2, p.y, p.x + p.width - (bd.right.width + 1) / 2, p.y + p.height));
    m_painter->restore();
}

void HtmlContainer::on_anchor_click(const char* url, const litehtml::element::ptr&) {
    if (onAnchor)
        onAnchor(QString::fromUtf8(url));
}

void HtmlContainer::set_cursor(const char* cursor) {
    if (onCursor)
        onCursor(QString::fromUtf8(cursor));
}

void HtmlContainer::transform_text(litehtml::string& text, litehtml::text_transform tt) {
    QString s = QString::fromUtf8(text.c_str());
    if (tt == litehtml::text_transform_uppercase) s = s.toUpper();
    else if (tt == litehtml::text_transform_lowercase) s = s.toLower();
    else if (tt == litehtml::text_transform_capitalize && !s.isEmpty()) s[0] = s[0].toUpper();
    text = s.toStdString();
}

void HtmlContainer::get_media_features(litehtml::media_features& media) const {
    media.type = litehtml::media_type_screen;
    media.width = media.device_width = m_width;
    media.height = media.device_height = m_height;
    media.color = 8;
    media.resolution = 96;
}

void HtmlContainer::get_language(litehtml::string& language, litehtml::string& culture) const {
    language = "en";
    culture = "";
}
