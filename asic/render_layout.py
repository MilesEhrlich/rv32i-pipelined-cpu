# Render a sky130 GDS to PNG with KLayout, showing cells and signal routing
# (the default render is dominated by the top-metal power grid).
#   klayout -b -r asic/render_layout.py -rd gds=cpu_core.gds -rd png=out.png
import pya

gds = globals().get("gds")
png = globals().get("png", "layout.png")
size = int(globals().get("size", "1600"))

# (layer, datatype, fill color, frame color, dither pattern, label)
LAYERS = [
    (65, 20, 0x1b5e20, 0x1b5e20, 0,  "diff"),
    (66, 20, 0x7b1f1f, 0x7b1f1f, 0,  "poly"),
    (68, 20, 0x1e88e5, 0x1e88e5, 0,  "met1"),
    (69, 20, 0xffb300, 0xffb300, 0,  "met2"),
    (70, 20, 0xe53935, 0xe53935, 0,  "met3"),
]

view = pya.LayoutView()
view.load_layout(gds, 0)
view.max_hier()
view.clear_layers()
view.set_config("background-color", "#0b0f14")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
for layer, dt, fill, frame, dither, name in LAYERS:
    lp = pya.LayerPropertiesNode()
    lp.source = f"{layer}/{dt}@1"
    lp.fill_color = fill
    lp.frame_color = frame
    lp.dither_pattern = dither
    lp.transparent = False
    lp.width = 0
    lp.name = name
    view.insert_layer(view.end_layers(), lp)
view.zoom_fit()
view.save_image(png, size, size)
print(f"wrote {png}")
