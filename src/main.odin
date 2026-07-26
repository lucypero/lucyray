package main

import "core:fmt"
import "core:os"
import "core:io"
import "core:strings"
import "core:math/linalg"

// constants

aspect_ratio :: 16.0 / 9.0
image_width: int = 400

focal_length :: 1
viewport_height :: 2

v3 :: [3]f32
point3 :: v3
Color :: v3

mag :: linalg.vector_length

main :: proc() {

	sb := strings.builder_make()

	// Image

	image_height : int = max(1, cast(int)(cast(f32)image_width / aspect_ratio))

	// Camera

	viewport_width : f32 = viewport_height * (cast(f32)image_width / cast(f32)image_height)
	camera_center := point3{}

	// Calculate the vectors across the horizontal and down the vertical viewport edges.
	viewport_u := v3{viewport_width, 0, 0}
	viewport_v := v3{0, -viewport_height, 0}

	// Calculate the horizontal and vertical delta vectors from pixel to pixel.
	pixel_delta_u := viewport_u / cast(f32)image_width;
	pixel_delta_v := viewport_v / cast(f32)image_height;

	// Calculate the location of the upper left pixel.
	viewport_upper_left : point3 = camera_center - v3{0, 0, focal_length} - viewport_u / 2 - viewport_v / 2
	pixel00_loc : point3 = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v)


	// Render

	fmt.sbprintf(&sb, "P3\n%v %v\n255\n", image_width, image_height)

	for j:= 0; j < image_height ; j += 1 {

		fmt.printfln("Scanlines remaining: %v", image_height - j)

		for i:= 0; i < image_width ; i+= 1 {

			pixel_center : v3 = pixel00_loc + (cast(f32)i * pixel_delta_u) + (cast(f32)j * pixel_delta_v)
			ray_direction : v3 = pixel_center - camera_center

			ray := Ray{camera_center, ray_direction}

			pixel_color := ray_color(ray)
			write_color(&sb, pixel_color)
		}
	}

	fmt.printfln("Done.")

	// linalg.vector_length()
	err := os.write_entire_file_from_string("image.ppm", strings.to_string(sb))
	assert(err == os.General_Error.None)
}

Ray :: struct {
	orig: point3,
	dir: v3
}

ray_color :: proc(r: Ray) -> Color {

	if hit_sphere({0, 0, -1}, 0.5, r) {
		return Color{1, 0, 0}
	}

	unit_direction := linalg.vector_normalize(r.dir)

	a := 0.5 * (unit_direction.y + 1)

	return (1 - a) * Color{1,1,1} + a * Color{0.5, 0.7, 1.0}
}

ray_at :: proc(r: Ray, t: f32) -> point3 {
	return r.orig + t * r.dir
}

write_color :: proc(sb: ^strings.Builder, pixel_color: Color) {

	// Translate the [0,1] component values to the byte range [0,255].
	rbyte := cast(int)(255.999 * pixel_color.r)
	gbyte := cast(int)(255.999 * pixel_color.g)
	bbyte := cast(int)(255.999 * pixel_color.b)

	fmt.sbprintf(sb, "%v %v %v\n", rbyte, gbyte, bbyte)
}


hit_sphere :: proc(center: point3, radius: f32, r: Ray) -> bool {

	oc := center - r.orig

	a := linalg.dot(r.dir, r.dir)
	b := -2 * linalg.dot(r.dir, oc)
	c := linalg.dot(oc, oc) - radius * radius
	discriminant := b * b - 4 * a * c
	return discriminant >= 0
}
