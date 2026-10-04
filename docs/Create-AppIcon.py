"""Build the desktop icon from the widget's three identity colors."""
from pathlib import Path
from PIL import Image, ImageDraw

# Render at high resolution so small desktop sizes retain smooth edges.
project = Path(__file__).resolve().parent.parent
scale = 4
image = Image.new("RGBA", (256 * scale, 256 * scale))
draw = ImageDraw.Draw(image)

# Keep the dark dashboard tile visible on both light and dark desktops.
def rounded_box(bounds, radius, color, outline=None, width=1):
    draw.rounded_rectangle(
        tuple(value * scale for value in bounds),
        radius=radius * scale,
        fill=color,
        outline=outline,
        width=width * scale,
    )

rounded_box((8, 8, 248, 248), 44, "#161A23", "#475163", 4)
# Use blue, purple and sage bars to represent the three usage metrics.
for bounds, color in [
    ((43, 112, 87, 208), "#669CFF"),
    ((106, 48, 150, 208), "#A97BFF"),
    ((169, 80, 213, 208), "#91B8B0"),
]:
    rounded_box(bounds, 10, color)

# Include native Windows icon sizes rather than stretching one small bitmap.
image = image.resize((256, 256), Image.Resampling.LANCZOS)
image.save(project / "AIUsage-App.ico", sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
# Preserve the icon path used by existing shortcuts on other computers.
image.save(project / "AIUsage-Tricolor.ico", sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
# Keep a PNG preview for the README and future artwork changes.
image.save(project / "docs" / "screenshots" / "app-icon.png")
