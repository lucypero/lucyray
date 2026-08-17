package main

import "core:mem"
import "core:slice"
import "core:fmt"
// import "core:mem"
import mv "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:math"
import "core:math/rand"
import "core:time"
import stbi "vendor:stb/image"

// constants

SCENE_SELECT :: 2

INFINITY :: math.INF_F32
PI :: math.PI

viewport_height :: 2

v3 :: [3]f32
point3 :: v3
Color :: v3

mag :: linalg.vector_length

main :: proc() {
	time_start := time.now()
	switch SCENE_SELECT {
	case 0:
		do_scene_bouncing_balls()
	case 1:
		do_scene_checkered_balls()
	case 2:
		do_scene_earth()
	}
	time_after := time.now()
	fmt.printfln("Took %v", time.diff(time_start, time_after))
}

do_scene_earth :: proc() {
	world_list := make([dynamic]Hittable)

	tex_earth := texture_image_new("earthmap.jpg")
	mat_earth := Material{type = .Lambertian, texture = &tex_earth}

	append(&world_list, sphere_new_still({0,0,0}, 2, &mat_earth))

	cam := camera_init(Camera{
		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {0, 0, 12},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_checkered_balls :: proc() {

	world_list := make([dynamic]Hittable)

	tex_white := Texture(TextureSolid{Color{.9,.9,.9}})
	tex_black := Texture(TextureSolid{Color{.2,.3,.1}})
	tex_checker := Texture(TextureCheckered{1 / 0.32, &tex_white, &tex_black})

	mat_checkered := Material{type = .Lambertian, texture = &tex_checker}

	append(&world_list, sphere_new_still({0,-10,0}, 10, &mat_checkered))
	append(&world_list, sphere_new_still({0,10,0}, 10, &mat_checkered))

	cam := camera_init(Camera{
		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {13,2,3},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_bouncing_balls :: proc() {
	bvh_arena := arena_new()

	world := make([dynamic]Hittable, 0, 20, allocator = context.temp_allocator)

	material_ground := Material{albedo = {0.5,0.5,0.5}, type = .Lambertian}
	append(&world, sphere_new_still({ 0.0, -1000, 0}, 1000.0, &material_ground))

	for a := -11; a < 11 ; a+=1 {
		for b := -11; b < 11; b+=1 {
			choose_mat := random_double()
			center := v3{f32(a) + 0.9*random_double(), 0.2, f32(b) + 0.9*random_double()}

			if (linalg.length(center - point3{4, 0.2, 0}) > 0.9) {
				sphere_material, m_err  := mv.new(&bvh_arena, Material)
				ensure(m_err == .None)

				if (choose_mat < 0.8) {
					// diffuse
					albedo : Color = v3_random_range(0, 1) * v3_random_range(0, 1)
					sphere_material^ = Material{type = .Lambertian, albedo = albedo}
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{orig = center, dir = center2 - center}, 0.2, sphere_material))
				} else if (choose_mat < 0.95) {
					// metal
					albedo : Color = v3_random_range(0.5, 1)
					fuzz := random_double(0, 0.5)
					sphere_material^ = Material{type = .Metal, albedo = albedo, fuzz = fuzz}
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{orig = center, dir = center2 - center}, 0.2, sphere_material))
				} else {
					// glass
					sphere_material^ = Material{type = .Dielectric, refraction_index = 1.5}
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{orig = center, dir = center2 - center}, 0.2, sphere_material))
				}
			}
		}
	}

	material1 := Material{type = .Dielectric, refraction_index = 1.5}
	append(&world, sphere_new_still({0,1,0}, 1, &material1))

	material2 := Material{type = .Lambertian, albedo = {0.4,0.2,0.1}}
	append(&world, sphere_new_still({-4,1,0}, 1, &material2))

	material3 := Material{type = .Metal, albedo = {0.7, 0.6, 0.5}, fuzz = 0}
	append(&world, sphere_new_still({4,1,0}, 1, &material3))


	world_opt := bvh_node_new(world[:], &bvh_arena)
	free_all(context.temp_allocator)

	cam := camera_init(Camera{
		// frame quality
		image_width = 200,
		samples_per_pixel = 15,
		max_depth = 10,

		// camera parameters
		vfov = 20,

		lookfrom = {13,2,3},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0.6,
		focus_dist = 10,
	})

	camera_render(&cam, world_opt^)
}

Ray :: struct {
	orig: point3,
	dir: v3,
	tm:f32
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
	u, v: f32,
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
	AABB,
	BVH_Node
}

Sphere :: struct {
	center: Ray,
	radius: f32,
	mat: ^Material,
	bbox: AABB // TODO remember to init this
}

hittable_get_bounding_box :: proc(hittable: Hittable) -> AABB {
	switch inner in hittable {
	case Sphere:
		return inner.bbox
	case AABB:
		return inner
	case BVH_Node:
		return inner.bbox
	case:
		panic("cannot reach here")
	}
}

hittable_hit :: proc(hittable: Hittable, r: Ray, interval: Interval) -> (bool, HitRecord) {
	switch inner in hittable {
	case Sphere:
		sphere := inner

		current_center := ray_at(sphere.center, r.tm)
		oc := current_center - r.orig

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
		outward_normal := (rec.p - current_center) / sphere.radius;
		hr_set_face_normal(&rec, r, outward_normal)
		u, v := sphere_get_uv(sphere, outward_normal)
		rec.u = u
		rec.v = v
		return true, rec
	case AABB:
		return aabb_hit(inner, r, interval)
	case BVH_Node:
		return bvh_node_hit(inner, r, interval)
	case:
		panic("unsupported shape")
		// return false, {}
	}
}


// inits a sphere that is standing still
sphere_new_still :: proc(orig: v3, rad: f32, mat: ^Material) -> Sphere {
	// calculating bbox
	rvec := v3{rad, rad, rad}
	bbox := aabb_new(orig - rvec, orig + rvec)
	return Sphere{Ray{orig = orig}, rad, mat, bbox}
}

sphere_new_moving :: proc(center: Ray, rad: f32, mat: ^Material) -> Sphere {
	// calculating bbox
	rvec := v3{rad, rad, rad}
	box1 := aabb_new(ray_at(center, 0) - rvec, ray_at(center, 0) + rvec)
	box2 := aabb_new(ray_at(center, 1) - rvec, ray_at(center, 1) + rvec)
	bbox := aabb_union(box1, box2)
	return Sphere{center, rad, mat, bbox}
}

// p: a given point on the sphere of radius one, centered at the origin.
// u: returned value [0,1] of angle around the Y axis from X=-1.
// v: returned value [0,1] of angle from Y=-1 to Y=+1.
//     <1 0 0> yields <0.50 0.50>       <-1  0  0> yields <0.00 0.50>
//     <0 1 0> yields <0.50 1.00>       < 0 -1  0> yields <0.50 0.00>
//     <0 0 1> yields <0.25 0.50>       < 0  0 -1> yields <0.75 0.50>
sphere_get_uv :: proc(sph: Sphere, p: point3) -> (u, v: f32) {
	theta := math.acos(-p.y);
	phi := math.atan2(-p.z, p.x) + PI;

	u = phi / (2*PI)
	v = theta / PI

	return
}

hit_list :: proc(hittables: []Hittable, r: Ray, interval: Interval) -> (bool, HitRecord) {
	temp_rec : HitRecord
	hit_anything: bool
	closest_so_far := interval.max

	for hittable in hittables {
		did_hit, rec := hittable_hit(hittable, r, {interval.min, closest_so_far})
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

interval_size :: proc(i : Interval) -> f32 {
	return abs(i.max - i.min)
}

interval_expand :: proc(int: Interval, delta: f32) -> Interval {
	padding := delta / 2
	return Interval{int.min - padding, int.max + padding}
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

// Create the interval tightly enclosing the two input intervals.
interval_union :: proc(a, b: Interval) -> Interval {
	return Interval {
		a.min <= b.min ? a.min : b.min,
		a.max >= b.max ? a.max : b.max
	}
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
	vfov: f32, // vertical view angle (field of view)

	lookfrom : point3,   // Point camera is looking from
	lookat   :point3,  // Point camera is looking at
	vup      :v3,     // Camera-relative "up" direction

	defocus_angle :f32,  // Variation angle of rays through each pixel
	focus_dist :f32,    // Distance from camera lookfrom point to plane of perfect focus

	// Private
	pixel_samples_scale: f32, // Color scale factor for a sum of pixel samples
	sb: strings.Builder,
	pixel00_loc : point3,
	image_height: int,
	center: point3,
	pixel_delta_u : v3,
	pixel_delta_v : v3,
	u,v,w: v3,

	defocus_disk_u, defocus_disk_v: v3 // Defocus disk horizontal / vertical radius
}

camera_init :: proc(cam_init: Camera) -> (cam: Camera) {

	aspect_ratio :: 16.0 / 9.0

	cam = cam_init

	cam.center = cam.lookfrom

	cam.sb = strings.builder_make()
	cam.pixel_samples_scale = 1 / cast(f32)cam.samples_per_pixel;

	cam.image_height = max(1, cast(int)(cast(f32)cam.image_width / aspect_ratio))

	// Determine viewport dimensions.
	theta := degrees_to_radians(cam.vfov)
	h := linalg.tan(theta/2)
	viewport_height := 2 * h * cam.focus_dist;
	viewport_width : f32 = viewport_height * (cast(f32)cam.image_width / cast(f32)cam.image_height)

	// Calculate the u,v,w unit basis vectors for the camera coordinate frame.
	cam.w = linalg.normalize(cam.lookfrom - cam.lookat);
	cam.u = linalg.normalize(linalg.cross(cam.vup, cam.w));
	cam.v = linalg.cross(cam.w, cam.u);

	// Calculate the vectors across the horizontal and down the vertical viewport edges.
	viewport_u := viewport_width * cam.u // Vector across viewport horizontal edge
	viewport_v := viewport_height * -cam.v // Vector down viewport vertical edge

	// Calculate the horizontal and vertical delta vectors from pixel to pixel.
	cam.pixel_delta_u = viewport_u / cast(f32)cam.image_width;
	cam.pixel_delta_v = viewport_v / cast(f32)cam.image_height;

	// Calculate the location of the upper left pixel.
	viewport_upper_left : point3 = cam.center - (cam.focus_dist * cam.w) - viewport_u / 2 - viewport_v / 2
	cam.pixel00_loc = viewport_upper_left + 0.5 * (cam.pixel_delta_u + cam.pixel_delta_v)

	// Calculate the camera defocus disk basis vectors.
	defocus_radius := cam.focus_dist * linalg.tan(degrees_to_radians(cam.defocus_angle / 2));
	cam.defocus_disk_u = cam.u * defocus_radius;
	cam.defocus_disk_v = cam.v * defocus_radius;

	return cam
}

camera_defocus_disk_sample :: proc(cam: Camera) -> v3{
	// Returns a random point in the camera defocus disk.
	p := random_in_unit_disk()
	return cam.center + (p[0] * cam.defocus_disk_u) + (p[1] * cam.defocus_disk_v)
}

camera_render :: proc(cam: ^Camera, world: Hittable) {

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

camera_ray_color :: proc(cam: Camera, r: Ray, depth: int, world: Hittable) -> Color {

	// If we've exceeded the ray bounce limit, no more light is gathered.
	if depth <= 0 do return Color{0,0,0}

	// passing a limig min w a small number to avoid shadow acne
	hit, rec := hittable_hit(world, r, {0.001, INFINITY})

	if hit {
		attenuation, scatter, did_scatter := material_scatter(rec.mat^, r, rec)
		if did_scatter {
			return attenuation * camera_ray_color(cam, scatter, depth - 1, world)
		} else {
			return {}
		}
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

	ray_origin := (cam.defocus_angle <= 0) ? cam.center : camera_defocus_disk_sample(cam)
	ray_direction := pixel_sample - ray_origin
	ray_time := random_double()

	return Ray{ray_origin, ray_direction, ray_time}
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

random_int :: proc(min, max: int) -> int {
	return rand.int_range(min, max)
}

random_in_unit_disk :: proc() -> v3 {
	for {
		p := v3{random_double(-1,1), random_double(-1,1), 0}
		if (linalg.length2(p) < 1) {
			return p
		}
	}
}

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

v3_refract :: proc(uv: v3, n: v3, etai_over_etat : f32) -> v3 {
	cos_theta := min(linalg.dot(-uv, n), 1.0)
	r_out_perp : v3 = etai_over_etat * (uv + cos_theta*n)
	r_out_parallel : v3 = -linalg.sqrt(abs(1.0 - linalg.length2(r_out_perp))) * n
	return r_out_perp + r_out_parallel
}

random_on_hemisphere :: proc(normal: v3) -> v3 {
	on_unit_sphere := v3_random_unit_vector();
	// In the same hemisphere as the normal
	if linalg.dot(on_unit_sphere, normal) > 0 do return on_unit_sphere
	return -on_unit_sphere;
}

Material_Type :: enum {
	Lambertian,
	Metal,
	Dielectric
}

Material :: struct {
	texture: ^Texture,
	fuzz: f32,

	// Refractive index in vacuum or air, or the ratio of the material's refractive index over
	// the refractive index of the enclosing media
	albedo: Color, // Fallback used if texture is nil
	refraction_index: f32,
	type: Material_Type,
}

reflectance :: proc(cosine: f32, refraction_index: f32) -> f32 {
	// Use Schlick's approximation for reflectance.
	r0 := (1 - refraction_index) / (1 + refraction_index)
	r0 = r0*r0;
	return r0 + (1-r0)*linalg.pow((1 - cosine),5)
}

material_scatter :: proc(mat:Material, ray_in: Ray, rec: HitRecord) -> (attenuation: Color, scattered: Ray, did_scatter: bool) {
	did_scatter = true

	switch mat.type {
	case .Lambertian:
		scatter_direction := rec.normal + v3_random_unit_vector()

		if v3_is_near_zero(scatter_direction) {
			scatter_direction = rec.normal
		}

		scattered = Ray{rec.p, scatter_direction, ray_in.tm}
		attenuation = mat.texture == nil ? mat.albedo : texture_get_value(mat.texture^, rec.u, rec.v, rec.p)
		return
	case .Metal:
		reflected := v3_reflect(ray_in.dir, rec.normal)
		reflected = linalg.normalize(reflected) + (mat.fuzz * v3_random_unit_vector())
		scattered = Ray{rec.p, reflected, ray_in.tm}
		attenuation = mat.texture == nil ? mat.albedo : texture_get_value(mat.texture^, rec.u, rec.v, rec.p)
		did_scatter = linalg.dot(scattered.dir, rec.normal) > 0
		return
	case .Dielectric:
		attenuation = Color{1.0, 1.0, 1.0}
		ri : f32 = rec.front_face ? (1.0/mat.refraction_index) : mat.refraction_index
		unit_direction : v3 = linalg.normalize(ray_in.dir)

		cos_theta : f32 = min(linalg.dot(-unit_direction, rec.normal), 1.0)
		sin_theta : f32 = linalg.sqrt(1.0 - cos_theta*cos_theta)

		cannot_refract : bool = ri * sin_theta > 1.0
		direction: v3

		if (cannot_refract || reflectance(cos_theta, ri) > random_double()) {
			direction = v3_reflect(unit_direction, rec.normal)
		}
		else {
			direction = v3_refract(unit_direction, rec.normal, ri)
		}

		scattered = Ray{rec.p, direction, ray_in.tm}
	}

	return
}


AABB :: struct {
	x, y, z: Interval
}

aabb_new_empty :: proc() -> AABB {

	return AABB {
		x = interval_empty,
		y = interval_empty,
		z = interval_empty,
	}
}

// Treat the two points a and b as extrema for the bounding box, so we don't require a
// particular minimum/maximum coordinate order.
aabb_new :: proc(a, b: point3) -> AABB {
	return AABB {
		x = (a[0] <= b[0]) ? Interval{a[0], b[0]} : Interval{b[0], a[0]},
		y = (a[1] <= b[1]) ? Interval{a[1], b[1]} : Interval{b[1], a[1]},
		z = (a[2] <= b[2]) ? Interval{a[2], b[2]} : Interval{b[2], a[2]},
	}
}

// Returns the index of the longest axis of the bounding box.
aabb_longest_axis :: proc(aabb: AABB) -> int {
	x_s := interval_size(aabb.x)
	y_s := interval_size(aabb.y)
	z_s := interval_size(aabb.z)

	if x_s > y_s {
		return x_s > z_s ? 0 : 2;
	}
	else {
		return y_s > z_s ? 1 : 2;
	}
}

// constructs a AABB that encloses two input AABBs
aabb_union :: proc(box0, box1: AABB) -> AABB {
	return AABB {
		x = interval_union(box0.x, box1.x),
		y = interval_union(box0.y, box1.y),
		z = interval_union(box0.z, box1.z)
	}
}

aabb_get_axis_interval :: proc(aabb: AABB, axis_index: int) -> Interval {
	switch axis_index {
	case 0: return aabb.x
	case 1: return aabb.y
	case: return aabb.z
	}
}

aabb_hit :: #force_inline proc(aabb: AABB, r: Ray, ray_t : Interval) -> (bool, HitRecord) {

	ray_t := ray_t

	for axis in 0..<3 {

		ax := aabb_get_axis_interval(aabb, axis)

		adinv := 1.0 / r.dir[axis]

		t0 := (ax.min - r.orig[axis]) * adinv;
		t1 := (ax.max - r.orig[axis]) * adinv;

		if t0 < t1 {
			if t0 > ray_t.min do ray_t.min = t0
			if t1 < ray_t.max do ray_t.max = t1
		} else {
			if t1 > ray_t.min do ray_t.min = t1
			if t0 < ray_t.max do ray_t.max = t0
		}

		if (ray_t.max <= ray_t.min) {
			return false, HitRecord{}
		}
	}

	return true, HitRecord{}
}

HittableList :: struct {
	objects : [dynamic]Hittable,
	bbox: AABB,
}

hittable_list_add :: proc(hl : ^HittableList, object: Hittable) {
	append(&hl.objects, object)
	hl.bbox = aabb_union(hl.bbox, hittable_get_bounding_box(object))
}

BVH_Node :: struct {
	left, right: ^Hittable,
	bbox: AABB
}

box_compare :: proc(a, b: Hittable, axis_index: int) -> bool {
	a_axis_interval := aabb_get_axis_interval(hittable_get_bounding_box(a), axis_index)
	b_axis_interval := aabb_get_axis_interval(hittable_get_bounding_box(b), axis_index)
	return a_axis_interval.min < b_axis_interval.min
}

box_compare_x :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 0)
}

box_compare_y :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 1)
}

box_compare_z :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 2)
}

bvh_node_new :: proc(objects: []Hittable, allocator : ^mv.Arena) -> (res_hittable: ^Hittable) {

	err : mv.Allocator_Error
	res_hittable, err = mv.new_clone(allocator, Hittable(BVH_Node{}))
	ensure(err == .None)

	res := &res_hittable.(BVH_Node)

	// Build the bounding box of the span of source objects.
	res.bbox = aabb_new_empty()

	for obj in objects {
		res.bbox = aabb_union(res.bbox, hittable_get_bounding_box(obj))
	}

	axis := aabb_longest_axis(res.bbox)

	comparator := (axis == 0) ? box_compare_x: (axis == 1) ? box_compare_y : box_compare_z

	object_span := len(objects)

	mem_err : mv.Allocator_Error

	if (object_span == 1) {
		res.left, mem_err = mv.new_clone(allocator, objects[0])
		res.right = res.left
	} else if (object_span == 2) {
		res.left, mem_err = mv.new_clone(allocator, objects[0])
		res.right, mem_err  = mv.new_clone(allocator, objects[1])
	} else {
		slice.sort_by(objects, comparator)
		mid := object_span/2;
		res.left = bvh_node_new(objects[:mid], allocator)
		res.right = bvh_node_new(objects[mid:], allocator)
	}

	return
}

bvh_node_hit :: proc(bvh_node: BVH_Node, r: Ray, ray_t: Interval) -> (bool, HitRecord) {
	if did_hit, _ := aabb_hit(bvh_node.bbox, r, ray_t); !did_hit {
		return false, HitRecord{}
	}

	hit_left, rec := hittable_hit(bvh_node.left^, r, ray_t)
	hit_right, rec2 := hittable_hit(bvh_node.right^, r, Interval{ray_t.min, hit_left ? rec.t : ray_t.max})

	if hit_right {
		return true, rec2
	}

	if hit_left {
		return true, rec
	}

	return false, HitRecord{}
}

arena_new :: proc() -> mv.Arena {
	arena : mv.Arena
	arena_err := mv.arena_init_growing(&arena)
	ensure(arena_err == nil)
	return arena
}

TextureSolid :: struct {
	albedo: Color
}

TextureCheckered :: struct {
	inv_scale: f32,
	even: ^Texture,
	odd: ^Texture
}

TextureImage :: struct {
	width, height, nrChannels: i32,
	data : [^]byte,
}

Texture :: union #no_nil {
	TextureSolid,
	TextureCheckered,
	TextureImage,
}

texture_get_value :: proc(tex: Texture, u, v: f32, p: point3) -> Color {

	switch tex_inner in tex {
	case TextureSolid:
		return tex_inner.albedo
	case TextureCheckered:
		xInteger := int(math.floor(tex_inner.inv_scale * p.x))
		yInteger := int(math.floor(tex_inner.inv_scale * p.y))
		zInteger := int(math.floor(tex_inner.inv_scale * p.z))

		isEven := (xInteger + yInteger + zInteger) % 2 == 0

		return isEven ? texture_get_value(tex_inner.even^, u, v, p) : texture_get_value(tex_inner.odd^, u, v, p)
	case TextureImage:
		if (tex_inner.height <= 0) do return Color{1,1,1}

		// Clamp input texture coordinates to [0,1] x [1,0]
		u_c := interval_clamp({0, 1}, u)
		v_c := 1 - interval_clamp({0, 1}, v)

		i := int(u_c * cast(f32)tex_inner.width);
		j := int(v_c * cast(f32)tex_inner.height);

		// Sampling Image
		pixel := texture_image_get_pixel_data(tex_inner, i, j)

		color_scale : f32 = 1.0 / 255.0;
		return Color{color_scale*cast(f32)pixel[0], color_scale*cast(f32)pixel[1], color_scale*cast(f32)pixel[2]}
	case:
		panic("wut?")
	}
}

texture_image_new :: proc(image_path: string) -> Texture {
	tex_r := Texture(TextureImage{})
	tex_i := &tex_r.(TextureImage)

	image_path_cstr := strings.clone_to_cstring(image_path, context.temp_allocator)
	tex_i.data = stbi.load(image_path_cstr, &tex_i.width, &tex_i.height, &tex_i.nrChannels, 0)
	ensure(tex_i.data != nil)

	return tex_r
}

// Return the the 3  RGB bytes of the pixel at x,y. If there is no image
// data, returns magenta.
texture_image_get_pixel_data :: proc(tex: TextureImage, x, y: int) -> (res: [3]byte) {

	if (tex.data == nil) do return {255, 0, 255}

	x_i := math.clamp(x, 0, cast(int)tex.width)
	y_i := math.clamp(y, 0, cast(int)tex.height)

	bytes_per_pixel := cast(int)tex.nrChannels

	mem.copy(&res, &tex.data[y_i * (cast(int)tex.width * bytes_per_pixel) + x_i * bytes_per_pixel], 3)
	return
	// return bdata + y*bytes_per_scanline + x*bytes_per_pixel;
}
