/* clang-format off */
#[modes]

mode_quad =
mode_ninepatch = #define USE_NINEPATCH
mode_primitive = #define USE_PRIMITIVE
mode_attributes = #define USE_ATTRIBUTES
mode_instanced = #define USE_ATTRIBUTES \n#define USE_INSTANCING

#[specializations]

DISABLE_LIGHTING = false

#[vertex]

#ifdef USE_ATTRIBUTES
layout(location = 0) in vec2 vertex_attrib;
layout(location = 3) in vec4 color_attrib;
layout(location = 4) in vec2 uv_attrib;

layout(location = 10) in uvec4 bone_attrib;
layout(location = 11) in vec4 weight_attrib;

#ifdef USE_INSTANCING

layout(location = 1) in highp vec4 instance_xform0;
layout(location = 2) in highp vec4 instance_xform1;
layout(location = 5) in highp uvec4 instance_color_custom_data; // Color packed into xy, custom_data packed into zw for compatibility with 3D

#endif

#endif

// This needs to be outside clang-format so the ubo comment is in the right place
#ifdef MATERIAL_UNIFORMS_USED
layout(std140) uniform MaterialUniforms{ //ubo:4

#MATERIAL_UNIFORMS

};
#endif
/* clang-format on */
#include "canvas_uniforms_inc.glsl"
#include "stdlib_inc.glsl"

uniform sampler2D transforms_texture; //texunit:-1

out vec2 uv_interp;
out vec4 color_interp;
out vec2 vertex_interp;
flat out int draw_data_instance;

#ifdef USE_NINEPATCH

out vec2 pixel_size_interp;

#endif

#GLOBALS

void main() {
	vec4 instance_custom = vec4(0.0);
	draw_data_instance = gl_InstanceID;
#ifdef USE_PRIMITIVE

	//weird bug,
	//this works
	vec2 vertex;
	vec2 uv;
	vec4 color;

	if (gl_VertexID == 0) {
		vertex = draw_data[draw_data_instance].point_a;
		uv = draw_data[draw_data_instance].uv_a;
		color = vec4(unpackHalf2x16(draw_data[draw_data_instance].color_a_rg), unpackHalf2x16(draw_data[draw_data_instance].color_a_ba));
	} else if (gl_VertexID == 1) {
		vertex = draw_data[draw_data_instance].point_b;
		uv = draw_data[draw_data_instance].uv_b;
		color = vec4(unpackHalf2x16(draw_data[draw_data_instance].color_b_rg), unpackHalf2x16(draw_data[draw_data_instance].color_b_ba));
	} else {
		vertex = draw_data[draw_data_instance].point_c;
		uv = draw_data[draw_data_instance].uv_c;
		color = vec4(unpackHalf2x16(draw_data[draw_data_instance].color_c_rg), unpackHalf2x16(draw_data[draw_data_instance].color_c_ba));
	}
	uvec4 bones = uvec4(0, 0, 0, 0);
	vec4 bone_weights = vec4(0.0);

#elif defined(USE_ATTRIBUTES)
#ifdef USE_INSTANCING
	draw_data_instance = 0;
#endif
	vec2 vertex = vertex_attrib;
	vec4 color = color_attrib * draw_data[draw_data_instance].modulation;
	vec2 uv = uv_attrib;

	uvec4 bones = bone_attrib;
	vec4 bone_weights = weight_attrib;

#ifdef USE_INSTANCING
	vec4 instance_color = vec4(unpackHalf2x16(instance_color_custom_data.x), unpackHalf2x16(instance_color_custom_data.y));
	color *= instance_color;
	instance_custom = vec4(unpackHalf2x16(instance_color_custom_data.z), unpackHalf2x16(instance_color_custom_data.w));
#endif

#else

	vec2 vertex_base_arr[4] = vec2[](vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0));
	vec2 vertex_base = vertex_base_arr[gl_VertexID];

	vec2 uv = draw_data[draw_data_instance].src_rect.xy + abs(draw_data[draw_data_instance].src_rect.zw) * ((draw_data[draw_data_instance].flags & FLAGS_TRANSPOSE_RECT) != uint(0) ? vertex_base.yx : vertex_base.xy);
	vec4 color = draw_data[draw_data_instance].modulation;
	vec2 vertex = draw_data[draw_data_instance].dst_rect.xy + abs(draw_data[draw_data_instance].dst_rect.zw) * mix(vertex_base, vec2(1.0, 1.0) - vertex_base, lessThan(draw_data[draw_data_instance].src_rect.zw, vec2(0.0, 0.0)));
	uvec4 bones = uvec4(0, 0, 0, 0);

#endif

	mat4 model_matrix = mat4(vec4(draw_data[draw_data_instance].world_x, 0.0, 0.0), vec4(draw_data[draw_data_instance].world_y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(draw_data[draw_data_instance].world_ofs, 0.0, 1.0));

#ifdef USE_INSTANCING
	model_matrix = model_matrix * transpose(mat4(instance_xform0, instance_xform1, vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0)));
#endif // USE_INSTANCING

#if !defined(USE_ATTRIBUTES) && !defined(USE_PRIMITIVE)
	if (bool(draw_data[draw_data_instance].flags & FLAGS_USING_PARTICLES)) {
		//scale by texture size
		vertex /= draw_data[draw_data_instance].color_texture_pixel_size;
	}
#endif

#ifdef USE_POINT_SIZE
	float point_size = 1.0;
#endif
	{
#CODE : VERTEX
	}

#ifdef USE_NINEPATCH
	pixel_size_interp = abs(draw_data[draw_data_instance].dst_rect.zw) * vertex_base;
#endif

#if !defined(SKIP_TRANSFORM_USED)
	vertex = (model_matrix * vec4(vertex, 0.0, 1.0)).xy;
#endif

	color_interp = color;

	if (use_pixel_snap) {
		vertex = floor(vertex + 0.5);
		// precision issue on some hardware creates artifacts within texture
		// offset uv by a small amount to avoid
		uv += 1e-5;
	}

#ifdef USE_ATTRIBUTES
#if 0
	if (bool(draw_data[draw_data_instance].flags & FLAGS_USE_SKELETON) && bone_weights != vec4(0.0)) { //must be a valid bone
		//skeleton transform
		ivec4 bone_indicesi = ivec4(bone_indices);

		uvec2 tex_ofs = bone_indicesi.x * 2;

		mat2x4 m;
		m = mat2x4(
					texelFetch(skeleton_buffer, tex_ofs + 0),
					texelFetch(skeleton_buffer, tex_ofs + 1)) *
			bone_weights.x;

		tex_ofs = bone_indicesi.y * 2;

		m += mat2x4(
					 texelFetch(skeleton_buffer, tex_ofs + 0),
					 texelFetch(skeleton_buffer, tex_ofs + 1)) *
			 bone_weights.y;

		tex_ofs = bone_indicesi.z * 2;

		m += mat2x4(
					 texelFetch(skeleton_buffer, tex_ofs + 0),
					 texelFetch(skeleton_buffer, tex_ofs + 1)) *
			 bone_weights.z;

		tex_ofs = bone_indicesi.w * 2;

		m += mat2x4(
					 texelFetch(skeleton_buffer, tex_ofs + 0),
					 texelFetch(skeleton_buffer, tex_ofs + 1)) *
			 bone_weights.w;

		mat4 bone_matrix = skeleton_data.skeleton_transform * transpose(mat4(m[0], m[1], vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0))) * skeleton_data.skeleton_transform_inverse;

		//outvec = bone_matrix * outvec;
	}
#endif
#endif

	vertex = (canvas_transform * vec4(vertex, 0.0, 1.0)).xy;

	vertex_interp = vertex;
	uv_interp = uv;

	gl_Position = screen_transform * vec4(vertex, 0.0, 1.0);

#ifdef USE_POINT_SIZE
	gl_PointSize = point_size;
#endif
}

#[fragment]

#include "canvas_uniforms_inc.glsl"
#include "stdlib_inc.glsl"

//uniform sampler2D atlas_texture; //texunit:-2
//uniform sampler2D shadow_atlas_texture; //texunit:-3
uniform sampler2D screen_texture; //texunit:-4
uniform sampler2D sdf_texture; //texunit:-5
uniform sampler2D normal_texture; //texunit:-6
uniform sampler2D specular_texture; //texunit:-7

uniform sampler2D color_texture; //texunit:0

in vec2 uv_interp;
in vec4 color_interp;
in vec2 vertex_interp;
flat in int draw_data_instance;

#ifdef USE_NINEPATCH

in vec2 pixel_size_interp;

#endif

layout(location = 0) out vec4 frag_color;

#ifdef MATERIAL_UNIFORMS_USED
layout(std140) uniform MaterialUniforms{
//ubo:4

#MATERIAL_UNIFORMS

};
#endif

#GLOBALS

#ifdef USE_NINEPATCH

float map_ninepatch_axis(float pixel, float draw_size, float tex_pixel_size, float margin_begin, float margin_end, int np_repeat, inout int draw_center) {
	float tex_size = 1.0 / tex_pixel_size;

	if (pixel < margin_begin) {
		return pixel * tex_pixel_size;
	} else if (pixel >= draw_size - margin_end) {
		return (tex_size - (draw_size - pixel)) * tex_pixel_size;
	} else {
		if (!bool(draw_data[draw_data_instance].flags & FLAGS_NINEPACH_DRAW_CENTER)) {
			draw_center--;
		}

		// np_repeat is passed as uniform using NinePatchRect::AxisStretchMode enum.
		if (np_repeat == 0) { // Stretch.
			// Convert to ratio.
			float ratio = (pixel - margin_begin) / (draw_size - margin_begin - margin_end);
			// Scale to source texture.
			return (margin_begin + ratio * (tex_size - margin_begin - margin_end)) * tex_pixel_size;
		} else if (np_repeat == 1) { // Tile.
			// Convert to offset.
			float ofs = mod((pixel - margin_begin), tex_size - margin_begin - margin_end);
			// Scale to source texture.
			return (margin_begin + ofs) * tex_pixel_size;
		} else if (np_repeat == 2) { // Tile Fit.
			// Calculate scale.
			float src_area = draw_size - margin_begin - margin_end;
			float dst_area = tex_size - margin_begin - margin_end;
			float scale = max(1.0, floor(src_area / max(dst_area, 0.0000001) + 0.5));
			// Convert to ratio.
			float ratio = (pixel - margin_begin) / src_area;
			ratio = mod(ratio * scale, 1.0);
			// Scale to source texture.
			return (margin_begin + ratio * dst_area) * tex_pixel_size;
		} else { // Shouldn't happen, but silences compiler warning.
			return 0.0;
		}
	}
}

#endif

float msdf_median(float r, float g, float b, float a) {
	return min(max(min(r, g), min(max(r, g), b)), a);
}

void main() {
	vec4 color = color_interp;
	vec2 uv = uv_interp;
	vec2 vertex = vertex_interp;

#if !defined(USE_ATTRIBUTES) && !defined(USE_PRIMITIVE)

#ifdef USE_NINEPATCH

	int draw_center = 2;
	uv = vec2(
			map_ninepatch_axis(pixel_size_interp.x, abs(draw_data[draw_data_instance].dst_rect.z), draw_data[draw_data_instance].color_texture_pixel_size.x, draw_data[draw_data_instance].ninepatch_margins.x, draw_data[draw_data_instance].ninepatch_margins.z, int(draw_data[draw_data_instance].flags >> FLAGS_NINEPATCH_H_MODE_SHIFT) & 0x3, draw_center),
			map_ninepatch_axis(pixel_size_interp.y, abs(draw_data[draw_data_instance].dst_rect.w), draw_data[draw_data_instance].color_texture_pixel_size.y, draw_data[draw_data_instance].ninepatch_margins.y, draw_data[draw_data_instance].ninepatch_margins.w, int(draw_data[draw_data_instance].flags >> FLAGS_NINEPATCH_V_MODE_SHIFT) & 0x3, draw_center));

	if (draw_center == 0) {
		color.a = 0.0;
	}

	uv = uv * draw_data[draw_data_instance].src_rect.zw + draw_data[draw_data_instance].src_rect.xy; //apply region if needed

#endif
	if (bool(draw_data[draw_data_instance].flags & FLAGS_CLIP_RECT_UV)) {
		uv = clamp(uv, draw_data[draw_data_instance].src_rect.xy, draw_data[draw_data_instance].src_rect.xy + abs(draw_data[draw_data_instance].src_rect.zw));
	}

#endif

#ifndef USE_PRIMITIVE
	if (bool(draw_data[draw_data_instance].flags & FLAGS_USE_MSDF)) {
		float px_range = draw_data[draw_data_instance].ninepatch_margins.x;
		float outline_thickness = draw_data[draw_data_instance].ninepatch_margins.y;
		//float reserved1 = draw_data[draw_data_instance].ninepatch_margins.z;
		//float reserved2 = draw_data[draw_data_instance].ninepatch_margins.w;

		vec4 msdf_sample = texture(color_texture, uv);
		vec2 msdf_size = vec2(textureSize(color_texture, 0));
		vec2 dest_size = vec2(1.0) / fwidth(uv);
		float px_size = max(0.5 * dot((vec2(px_range) / msdf_size), dest_size), 1.0);
		float d = msdf_median(msdf_sample.r, msdf_sample.g, msdf_sample.b, msdf_sample.a) - 0.5;

		if (outline_thickness > 0.0) {
			float cr = clamp(outline_thickness, 0.0, px_range / 2.0) / px_range;
			float a = clamp((d + cr) * px_size, 0.0, 1.0);
			color.a = a * color.a;
		} else {
			float a = clamp(d * px_size + 0.5, 0.0, 1.0);
			color.a = a * color.a;
		}
	} else if (bool(draw_data[draw_data_instance].flags & FLAGS_USE_LCD)) {
		vec4 lcd_sample = texture(color_texture, uv);
		if (lcd_sample.a == 1.0) {
			color.rgb = lcd_sample.rgb * color.a;
		} else {
			color = vec4(0.0, 0.0, 0.0, 0.0);
		}
	} else {
#else
	{
#endif
		color *= texture(color_texture, uv);
	}

	bool using_light = false;

	vec3 normal;

#if defined(NORMAL_USED)
	bool normal_used = true;
#else
	bool normal_used = false;
#endif

	if (normal_used || (using_light && bool(draw_data[draw_data_instance].flags & FLAGS_DEFAULT_NORMAL_MAP_USED))) {
		normal.xy = texture(normal_texture, uv).xy * vec2(2.0, -2.0) - vec2(1.0, -1.0);
		normal.z = sqrt(1.0 - dot(normal.xy, normal.xy));
		normal_used = true;
	} else {
		normal = vec3(0.0, 0.0, 1.0);
	}

	vec4 specular_shininess;

#if defined(SPECULAR_SHININESS_USED)

	bool specular_shininess_used = true;
#else
	bool specular_shininess_used = false;
#endif

	if (specular_shininess_used || (using_light && normal_used && bool(draw_data[draw_data_instance].flags & FLAGS_DEFAULT_SPECULAR_MAP_USED))) {
		specular_shininess = texture(specular_texture, uv);
		specular_shininess *= unpackUnorm4x8(draw_data[draw_data_instance].specular_shininess);
		specular_shininess_used = true;
	} else {
		specular_shininess = vec4(1.0);
	}

#if defined(SCREEN_UV_USED)
	vec2 screen_uv = gl_FragCoord.xy * screen_pixel_size;
#else
	vec2 screen_uv = vec2(0.0);
#endif

	vec3 light_vertex = vec3(vertex, 0.0);
	vec2 shadow_vertex = vertex;

	{
		float normal_map_depth = 1.0;

#if defined(NORMAL_MAP_USED)
		vec3 normal_map = vec3(0.0, 0.0, 1.0);
		normal_used = true;
#endif

#CODE : FRAGMENT

#if defined(NORMAL_MAP_USED)
		normal = mix(vec3(0.0, 0.0, 1.0), normal_map * vec3(2.0, -2.0, 1.0) - vec3(1.0, -1.0, 0.0), normal_map_depth);
#endif
	}

#ifdef MODE_LIGHT_ONLY
	color = vec4(0.0);
#else
	color *= canvas_modulation;
#endif

	frag_color = color;
}
