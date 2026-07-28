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

viewport_height :: 2

v3 :: [3]f32
point3 :: v3
Color :: v3

mag :: linalg.vector_length

main :: proc() {
	world := make([dynamic]Hittable, 0, 20)
	append(&world, Sphere{{0, 0, -1}, 0.5})
	append(&world, Sphere{{0, -100.5, -1}, 100})

	cam := camera_init()
	camera_render(&cam, world[:])
}

Ray :: struct {
	orig: point3,
	dir: v3
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

Hittable :: union {
	Sphere,
}

Sphere :: struct {
	center: point3,
	radius: f32,
}


hit :: proc(hittable: Hittable, r: Ray, interval: Interval) -> (bool, HitRecord) {
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

		if !interval_surrounds(interval, root) {
			root = (h + sqrtd) / a
			if !interval_surrounds(interval, root) do return false, {}
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

hit_list :: proc(hittables: []Hittable, r: Ray, interval: Interval) -> (bool, HitRecord) {
	temp_rec : HitRecord
	hit_anything: bool
	closest_so_far := interval.max

	for hittable in hittables {
		did_hit, rec := hit(hittable, r, {interval.min, closest_so_far})
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

// Interval

Interval :: struct {
	min, max: f32
}

interval_new :: proc() -> Interval {
	return {+INFINITY, -INFINITY}
}

interval_contains :: proc(i: Interval, x: f32) -> bool {
	return i.min <= x && x <= i.max;
}

interval_surrounds :: proc(i: Interval, x: f32) -> bool {
	return i.min < x && x < i.max;
}

@rodata
interval_empty := Interval{+INFINITY, -INFINITY}

@rodata
interval_universe := Interval{-INFINITY, +INFINITY}



Camera :: struct {

	// Public
	image_width: int,

	// Private
	sb: strings.Builder,
	pixel00_loc : point3,
	image_height: int,
	center: point3,
	pixel_delta_u : v3,
	pixel_delta_v : v3
}

camera_init :: proc() -> (cam: Camera) {
	focal_length :: 1
	aspect_ratio :: 16.0 / 9.0


	cam.sb = strings.builder_make()
	cam.image_width = 400
	cam.image_height = max(1, cast(int)(cast(f32)cam.image_width / aspect_ratio))

	viewport_width : f32 = viewport_height * (cast(f32)cam.image_width / cast(f32)cam.image_height)

	// Calculate the vectors across the horizontal and down the vertical viewport edges.
	viewport_u := v3{viewport_width, 0, 0}
	viewport_v := v3{0, -viewport_height, 0}

	// Calculate the horizontal and vertical delta vectors from pixel to pixel.
	cam.pixel_delta_u = viewport_u / cast(f32)cam.image_width;
	cam.pixel_delta_v = viewport_v / cast(f32)cam.image_height;

	// Calculate the location of the upper left pixel.
	viewport_upper_left : point3 = cam.center - v3{0, 0, focal_length} - viewport_u / 2 - viewport_v / 2
	cam.pixel00_loc = viewport_upper_left + 0.5 * (cam.pixel_delta_u + cam.pixel_delta_v)

	return cam
}

camera_render :: proc(cam: ^Camera, world: []Hittable) {

	fmt.sbprintf(&cam.sb, "P3\n%v %v\n255\n", cam.image_width, cam.image_height)

	for j:= 0; j < cam.image_height ; j += 1 {

		fmt.printfln("Scanlines remaining: %v", cam.image_height - j)

		for i:= 0; i < cam.image_width ; i+= 1 {

			pixel_center : v3 = cam.pixel00_loc + (cast(f32)i * cam.pixel_delta_u) + (cast(f32)j * cam.pixel_delta_v)
			ray_direction : v3 = pixel_center - cam.center

			ray := Ray{cam.center, ray_direction}

			pixel_color := camera_ray_color(cam^, ray, world)
			write_color(&cam.sb, pixel_color)
		}
	}

	fmt.printfln("Done.")

	// linalg.vector_length()
	err := os.write_entire_file_from_string("image.ppm", strings.to_string(cam.sb))
	assert(err == os.General_Error.None)

	strings.builder_reset(&cam.sb)
}

camera_ray_color :: proc(cam: Camera, r: Ray, world: []Hittable) -> Color {
	hit, rec := hit_list(world, r, {0, INFINITY})
	if hit {
		return 0.5 * (rec.normal + 1)
	}

	unit_direction := linalg.vector_normalize(r.dir)
	a := 0.5 * (unit_direction.y + 1)
	return (1 - a) * Color{1,1,1} + a * Color{0.5, 0.7, 1.0}
}
