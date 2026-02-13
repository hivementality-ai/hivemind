# frozen_string_literal: true

module IconHelper
  # Main Hivemind logo — hexagonal beehive line art
  def hivemind_logo(size: "w-8 h-8", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 32 32", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        # Outer hexagon
        tag.path(d: "M16 2L28 9V23L16 30L4 23V9L16 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        # Inner honeycomb cells — 3 hexagons
        tag.path(d: "M16 8L20.5 10.5V15.5L16 18L11.5 15.5V10.5L16 8Z", stroke: "currentColor", "stroke-width": "1.2", "stroke-linejoin": "round", opacity: "0.8"),
        tag.path(d: "M10 15L14.5 17.5V22.5L10 25L5.5 22.5V17.5L10 15Z", stroke: "currentColor", "stroke-width": "1.2", "stroke-linejoin": "round", opacity: "0.6"),
        tag.path(d: "M22 15L26.5 17.5V22.5L22 25L17.5 22.5V17.5L22 15Z", stroke: "currentColor", "stroke-width": "1.2", "stroke-linejoin": "round", opacity: "0.6")
      ])
    end
  end

  # Compact hex icon for small spaces (sidebar, favicons)
  def hex_icon(size: "w-6 h-6", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        tag.path(d: "M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        tag.path(d: "M12 7L16 9.5V14.5L12 17L8 14.5V9.5L12 7Z", stroke: "currentColor", "stroke-width": "1.2", "stroke-linejoin": "round", opacity: "0.7")
      ])
    end
  end

  # Tool/gear hexagon
  def hex_tool_icon(size: "w-5 h-5", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        tag.path(d: "M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        tag.path(d: "M14.5 12a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z", stroke: "currentColor", "stroke-width": "1.2"),
        tag.path(d: "M12 7v2m0 6v2m-4.33-7.5l1.73 1m5.2 3l1.73 1m-8.66 0l1.73-1m5.2-3l1.73-1", stroke: "currentColor", "stroke-width": "1", "stroke-linecap": "round", opacity: "0.6")
      ])
    end
  end

  # Lightning bolt in hexagon (for platform/triggers)
  def hex_bolt_icon(size: "w-5 h-5", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        tag.path(d: "M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        tag.path(d: "M13 7L9 13h3l-1 5 5-7h-3.5L13 7z", fill: "currentColor", opacity: "0.8")
      ])
    end
  end

  # Chat bubble in hexagon
  def hex_chat_icon(size: "w-5 h-5", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        tag.path(d: "M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        tag.path(d: "M8 10h8M8 13h5", stroke: "currentColor", "stroke-width": "1.2", "stroke-linecap": "round", opacity: "0.7")
      ])
    end
  end

  # Link/integration hexagon
  def hex_link_icon(size: "w-5 h-5", css: "")
    content_tag(:svg, class: "#{size} #{css}", viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg") do
      safe_join([
        tag.path(d: "M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z", stroke: "currentColor", "stroke-width": "1.5", "stroke-linejoin": "round"),
        tag.path(d: "M10 14l4-4m-4.5 1.5a2.12 2.12 0 01-3-3l1-1a2.12 2.12 0 013 0m3 1a2.12 2.12 0 013 3l-1 1a2.12 2.12 0 01-3 0", stroke: "currentColor", "stroke-width": "1.2", "stroke-linecap": "round", opacity: "0.7")
      ])
    end
  end
end
