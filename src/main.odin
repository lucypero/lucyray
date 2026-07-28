package main

import "core:fmt"
import "core:os"
import "core:io"
import "core:strings"
import "core:math/linalg"
import "core:math"

// constants

INFINITY :: math.INF_F32
PI :: math.PI

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

	// world

	world := make([dynamic]Hittable, 0, 20)
	append(&world, Sphere{{0, 0, -1}, 0.5})
	append(&world, Sphere{{0, -100.5, -1}, 100})

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

			pixel_color := ray_color(ray, world[:])
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

ray_color :: proc(r: Ray, world: []Hittable) -> Color {
	hit, rec := hit_list(world, r, 0, INFINITY)
	if hit {
		return 0.5 * (rec.normal + 1)
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


HitRecord :: struct {
	p: point3,
	normal: v3,
	t: f32,
	front_face: bool
}

// Sets the hit record normal vector.
// NOTE: the parameter `outward_normal` is assumed to have unit length.
hr_set_face_normal :: proc(hr: ^HitRecord, r: Ray, outward_normal: v3) {
	hr.front_face = linalg.dot(r.dir, outward_normal) < 0
	hr.normal = hr.front_face ? outward_normal : -outward_normal
}

HitProc :: proc(r: Ray, ray_tmin, ray_tmax: f32) -> (bool, HitRecord)

Hittable :: union {
	Sphere,
}

Sphere :: struct {
	center: point3,
	radius: f32,
}


hit :: proc(hittable: Hittable, r: Ray, ray_tmin, ray_tmax: f32) -> (bool, HitRecord) {
	switch inner in hittable {
	case Sphere:
		sphere := inner
		oc := sphere.center - r.orig

		a := linalg.length2(r.dir)
		h := linalg.dot(r.dir, oc)
		c := linalg.length2(oc) - (sphere.radius * sphere.radius)

		discriminant := h*h - a*c

		if discriminant < 0 do return false, {}

		sqrtd := linalg.sqrt(discriminant)

		// // Find the nearest root that lies in the acceptable range.
		root := (h - sqrtd) / a
		if root <= ray_tmin || ray_tmax <= root {
			root = (h + sqrtd) / a
			if root <= ray_tmin || ray_tmax <= root do return false, {}
		}

		rec : HitRecord
		rec.t = root
		rec.p = ray_at(r, rec.t)
		outward_normal := (rec.p - sphere.center) / sphere.radius;
		hr_set_face_normal(&rec, r, outward_normal);

		return true, rec
	case:
		panic("unsupported shape")
		// return false, {}
	}
}

hit_list :: proc(hittables: []Hittable, r: Ray, ray_tmin, ray_tmax: f32) -> (bool, HitRecord) {
	temp_rec : HitRecord
	hit_anything: bool
	closest_so_far := ray_tmax

	for hittable in hittables {
		did_hit, rec := hit(hittable, r, ray_tmin, closest_so_far)
		if did_hit {
			hit_anything = true
			closest_so_far = rec.t
			temp_rec = rec
		}
	}

	return hit_anything, temp_rec
}


// bool hit(const ray& r, double ray_tmin, double ray_tmax, hit_record& rec) const override {
//     hit_record temp_rec;
//     bool hit_anything = false;
//     auto closest_so_far = ray_tmax;

//     for (const auto& object : objects) {
//         if (object->hit(r, ray_tmin, closest_so_far, temp_rec)) {
//             hit_anything = true;
//             closest_so_far = temp_rec.t;
//             rec = temp_rec;
//         }
//     }

//     return hit_anything;
// }

degrees_to_radians :: proc(degrees: f32) -> f32 {
	return degrees * PI / 180
}
