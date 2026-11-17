shader_type canvas_item;
render_mode unshaded, blend_mix;

// Turns a background tile layer into a silhouette mask.
//
// The room's `BackTiles` layer is cloned into a small room-sized SubViewport once
// per room and drawn with this material: every opaque tile pixel becomes white,
// transparent pixels stay transparent. The result is the alpha shape of the
// background tile layer, which is exactly what the drop shadow needs — a tile
// render would keep the art's colours, and a fully opaque tile has no soft edge
// to blur inside itself, so the blur has to happen on the room-sized silhouette.

void fragment() {
	// The tile atlas alpha is the silhouette; the RGB is irrelevant.
	float coverage = texture(TEXTURE, UV).a;
	COLOR = vec4(1.0, 1.0, 1.0, coverage);
}
