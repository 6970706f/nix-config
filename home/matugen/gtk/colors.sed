# Flat-Remix-GTK-White-Darkest -> matugen tokens. The theme writes its accent as #ffffff and
# its accent text as #000000, but plain text and base as the keywords white and black, which
# is what lets them take different colors here. Reds, oranges and greens keep their meaning
# on any wallpaper, and rgba(0, 0, 0, ...) stays because those are shadows.


# On backgrounds, white and light grays are the accent and its hover and active shades.
/background(-image)?:/ {
  s/([ (,:])white([ ;,)])/\1{{colors.primary.default.hex}}\2/g
  s/#fafafa\b/shade({{colors.primary.default.hex}}, 0.98)/g
  s/#f2f2f2\b/shade({{colors.primary.default.hex}}, 0.95)/g
  s/#ededed\b/shade({{colors.primary.default.hex}}, 0.93)/g
  s/#e0e0e0\b/shade({{colors.primary.default.hex}}, 0.88)/g
  s/#d9d9d9\b/shade({{colors.primary.default.hex}}, 0.85)/g
  s/#d6d6d6\b/shade({{colors.primary.default.hex}}, 0.84)/g
  s/#cfcfcf\b/shade({{colors.primary.default.hex}}, 0.81)/g
  s/#cacaca\b/shade({{colors.primary.default.hex}}, 0.79)/g
}
s/#dbdbdb\b/shade({{colors.primary.default.hex}}, 0.86)/g
# Accent
s/#ffffff\b/{{colors.primary.default.hex}}/g
s/#fff\b/{{colors.primary.default.hex}}/g
s/#000000\b/{{colors.on_primary.default.hex}}/g
s/#(e6e6e6|2777ff)\b/{{colors.primary.default.hex}}/g
s/#19a187\b/{{colors.tertiary.default.hex}}/g
s/#(303340|272a34)\b/{{colors.secondary_container.default.hex}}/g
s/#(4a5063|383c4a)\b/{{colors.outline_variant.default.hex}}/g

# Keywords, only where they are values
s/([ (,:])white([ ;,)])/\1{{colors.on_surface.default.hex}}\2/g
s/([ (,:])black([ ;,)])/\1{{colors.surface_container_lowest.default.hex}}\2/g

# Gray ramp, darkest to lightest
s/#(010101|030303|050505|060606|080808|090909|0a0a0a)\b/{{colors.surface_container_lowest.default.hex}}/g
s/#(0b0b0b|0d0d0d|0f0f0f)\b/{{colors.background.default.hex}}/g
s/#(121212|131313|171717|181818)\b/{{colors.surface_container_low.default.hex}}/g
s/#(1a1a1a|242424)\b/{{colors.surface_container.default.hex}}/g
s/#(1f1f1f|262626|2b2b2b|2e2e2e|303030|30302f)\b/{{colors.surface_container_high.default.hex}}/g
s/#(333333|3a3a39|404040|40403f|454544)\b/{{colors.surface_container_highest.default.hex}}/g
s/#(4d4d4d|505050|515151|585858|656564|666666|6d6d6d|6e6d71)\b/{{colors.outline_variant.default.hex}}/g
s/#(717170|777776|7d7d7c|7f7f7f|868686|888a85|8b8e8f|8d8d8d|909090|949493|97999f|999999)\b/{{colors.outline.default.hex}}/g
s/#(b0b2b2|b3b3b1|b3b3b3|bebebd|c0bfbc|c1c1bf|cacaca|cccccc|cdcdcd|cfcfcf)\b/{{colors.on_surface_variant.default.hex}}/g
s/#(d6d6d4|d6d6d6|d8d7d3|d9d9d9|e0e0e0|eaeaea|ededed|eeeeec|f0f0f0|f2f2f2|fafafa|fdfdfd)\b/{{colors.on_surface.default.hex}}/g

# Translucent versions of the same colors. alpha() works in both GTK 3 and GTK 4 CSS.
s/rgba\(25[45], 25[45], 25[45], ([0-9.]+)\)/alpha({{colors.primary.default.hex}}, \1)/g
s/rgba\((238, 238, 236|219, 219, 219|230, 230, 230), ([0-9.]+)\)/alpha({{colors.on_surface.default.hex}}, \2)/g
s/rgba\(179, 179, 179, ([0-9.]+)\)/alpha({{colors.on_surface_variant.default.hex}}, \1)/g
s/rgba\((125, 125, 124|148, 148, 147), ([0-9.]+)\)/alpha({{colors.outline.default.hex}}, \2)/g
s/rgba\((58, 58, 57|51, 51, 51|68, 72, 83), ([0-9.]+)\)/alpha({{colors.surface_container_highest.default.hex}}, \2)/g
s/rgba\((31, 31, 31|39, 42, 52|23, 28, 36), ([0-9.]+)\)/alpha({{colors.surface_container_high.default.hex}}, \2)/g
s/rgba\((5, 5, 5|8, 8, 8|13, 13, 13), ([0-9.]+)\)/alpha({{colors.background.default.hex}}, \2)/g
