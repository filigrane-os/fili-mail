#include "html.h"
#include "el_td.h"


litehtml::el_td::el_td(const std::shared_ptr<document>& doc) : html_tag(doc)
{

}

void litehtml::el_td::parse_attributes()
{
	const char* str = get_attr("width");
	if(str)
	{
		m_style.add_property(_width_, str);
	}
	str = get_attr("background");
	if(str)
	{
		string url = "url('";
		url += str;
		url += "')";
		m_style.add_property(_background_image_, url);
	}
	str = get_attr("align");
	if(str)
	{
		m_style.add_property(_text_align_, str);
	}

	str = get_attr("bgcolor");
	if (str)
	{
		m_style.add_property(_background_color_, str, "", false, get_document()->container());
	}

	str = get_attr("valign");
	if(str)
	{
		m_style.add_property(_vertical_align_, str);
	}
	// Filigrane: the cellpadding of the table around gives its cells' padding (upstream kept the 1px default, so
	// every mail table with cellpadding="0" had a white line inside its buttons and cells)
	for(auto table = parent(); table; table = table->parent())
	{
		if(table->css().get_display() == display_table || (table->get_tagName() && !strcmp(table->get_tagName(), "table")))
		{
			// A padding the style sheets gave the cell wins, as in a browser
			const char* padding = m_style.get_property(_padding_top_).m_type == prop_type_invalid ? table->get_attr("cellpadding") : nullptr;
			if(padding)
			{
				string val = padding;
				if(!val.empty() && val.find_first_not_of("0123456789") == string::npos)
				{
					val += "px";
				}
				m_style.add_property(_padding_, val);
			}
			break;
		}
	}
	html_tag::parse_attributes();
}
