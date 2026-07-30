package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:math"
import "core:math/rand"

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

	material_ground := Material{albedo = {0.8, 0.8, 0}, type = .Lambertian}
	material_center := Material{albedo = {0.1, 0.2, 0.5}, type = .Lambertian}
	material_left := Material{albedo = {0.8, 0.8, 0.8}, type = .Metal}
	material_right := Material{albedo = {0.8, 0.6, 0.2}, type = .Metal}

	append(&world, Sphere{{0, -100.5, -1}, 100, &material_ground})

	append(&world, Sphere{{0, 0, -1.2}, 0.5, &material_center})
	append(&world, Sphere{{-1, 0, -1.0}, 0.5, &material_left})
	append(&world, Sphere{{1, 0, -1.0}, 0.5, &material_right})

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
	intensity := Interval{0, 0.999}

	// Apply a linear to gamma transform for gamma 2
	r := linear_to_gamma(pixel_color.r);
	g := linear_to_gamma(pixel_color.g);
	b := linear_to_gamma(pixel_color.b);

	rbyte := cast(int)(256 * interval_clamp(intensity, r))
	gbyte := cast(int)(256 * interval_clamp(intensity, g))
	bbyte := cast(int)(256 * interval_clamp(intensity, b))

	fmt.sbprintf(sb, "%v %v %v\n", rbyte, gbyte, bbyte)
}


HitRecord :: struct {
	p: point3,
	mat: ^Material,
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
	mat: ^Material, // TODO: remember to initialize this
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
		rec.mat = sphere.mat
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

interval_clamp :: proc(i: Interval, x: f32) -> f32 {
	return clamp(x, i.min, i.max)
}

@rodata
interval_empty := Interval{+INFINITY, -INFINITY}

@rodata
interval_universe := Interval{-INFINITY, +INFINITY}



Camera :: struct {

	// Public
	image_width: int,

	samples_per_pixel: int, // Count of random samples for each pixel
	max_depth: int,

	// Private
	pixel_samples_scale: f32, // Color scale factor for a sum of pixel samples
	sb: strings.Builder,
	pixel00_loc : point3,
	image_height: int,
	center: point3,
	pixel_delta_u : v3,
	pixel_delta_v : v3
}

camera_init :: proc() -> (cam: Camera) {

	// Setting public fields

	focal_length :: 1
	aspect_ratio :: 16.0 / 9.0
	cam.image_width = 400
	cam.samples_per_pixel = 50
	cam.max_depth = 10

	// /end

	cam.sb = strings.builder_make()
	cam.pixel_samples_scale = 1 / cast(f32)cam.samples_per_pixel;

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

			pixel_color : Color 

			for _ in 0 ..< cam.samples_per_pixel {
				r: Ray = camera_get_ray(cam^, i, j)
				pixel_color += camera_ray_color(cam^, r, cam.max_depth, world);
			}

			write_color(&cam.sb, cam.pixel_samples_scale * pixel_color)
		}
	}

	fmt.printfln("Done.")

	// linalg.vector_length()
	err := os.write_entire_file_from_string("image.ppm", strings.to_string(cam.sb))
	assert(err == os.General_Error.None)

	strings.builder_reset(&cam.sb)
}

camera_ray_color :: proc(cam: Camera, r: Ray, depth: int, world: []Hittable) -> Color {

	// If we've exceeded the ray bounce limit, no more light is gathered.
	if depth <= 0 do return Color{0,0,0}

	// passing a limig min w a small number to avoid shadow acne
	hit, rec := hit_list(world, r, {0.001, INFINITY})
	if hit {
		attenuation, scatter := material_scatter(rec.mat^, r, rec)
		return attenuation * camera_ray_color(cam, scatter, depth - 1, world)
	}

	unit_direction := linalg.vector_normalize(r.dir)
	a := 0.5 * (unit_direction.y + 1)
	return (1 - a) * Color{1,1,1} + a * Color{0.5, 0.7, 1.0}
}

linear_to_gamma :: proc(linear_component: f32) -> f32 {
	if linear_component > 0 do return linalg.sqrt(linear_component)
	return 0
}

// Construct a camera ray originating from the origin and directed at randomly sampled
// point around the pixel location i, j.
// ray get_ray(int i, int j) const {
camera_get_ray :: proc(cam: Camera, i, j: int) -> Ray {

	offset := sample_square();
	pixel_sample := cam.pixel00_loc +
	((f32(i) + offset.x) * cam.pixel_delta_u) +
	((f32(j) + offset.y) * cam.pixel_delta_v)

	ray_origin := cam.center
	ray_direction := pixel_sample - ray_origin

	return Ray{ray_origin, ray_direction}
}

// Returns the vector to a random point in the [-.5,-.5]-[+.5,+.5] unit square.
sample_square :: proc() -> v3 {
	return v3{random_double() - 0.5, random_double() - 0.5, 0}
}

// Returns a random real in [0,1).
random_double_norm :: proc() -> f32 {
	return rand.float32()
}

// Returns a random real in [min,max).
random_double_minmax :: proc(min, max: f32) -> f32 {
	return rand.float32_range(min, max)
}

random_double :: proc{random_double_norm, random_double_minmax}

v3_random_one :: proc () -> v3 {
	return v3{random_double(), random_double(), random_double()}
}

v3_random_range :: proc(min, max: f32) -> v3 {
	return v3{random_double(min,max), random_double(min,max), random_double(min,max)}
}

v3_random :: proc{v3_random_one, v3_random_range}

v3_random_unit_vector :: proc() -> v3 {
	for {
		p := v3_random(-1,1);
		lensq := linalg.length2(p)
		if (1e-160 < lensq && lensq <= 1) do return p / linalg.sqrt(lensq)
	}
}

v3_is_near_zero :: proc(v: v3) -> bool {
	s : f32 = 1e-8
	return abs(v.x) < s && (abs(v.y) < s) && (abs(v.z) < s)
}

v3_reflect :: proc(v: v3, n: v3) -> v3 {
	return v - 2*linalg.dot(v,n)*n;
}

random_on_hemisphere :: proc(normal: v3) -> v3 {
	on_unit_sphere := v3_random_unit_vector();
	// In the same hemisphere as the normal
	if linalg.dot(on_unit_sphere, normal) > 0 do return on_unit_sphere
	return -on_unit_sphere;
}

Material_Type :: enum {
	Lambertian,
	Metal
}

Material :: struct {
	albedo: Color,
	type: Material_Type,
}

material_scatter :: proc(mat:Material, ray_in: Ray, rec: HitRecord) -> (attenuation: Color, scattered: Ray) {
	switch mat.type {
	case .Lambertian:
		scatter_direction := rec.normal + v3_random_unit_vector()

		if v3_is_near_zero(scatter_direction) {
			scatter_direction = rec.normal
		}

		scattered = Ray{rec.p, scatter_direction}
		attenuation = mat.albedo
		return
	case .Metal:
		reflected := v3_reflect(ray_in.dir, rec.normal)
		scattered = Ray{rec.p, reflected}
		attenuation = mat.albedo
		return
	}

	return
}
