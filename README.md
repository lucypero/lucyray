# lucyray

![render collage](renders/collage.png)

My version of [Ray Tracing in One Weekend - The Book Series](https://raytracing.github.io/), [book 1](https://raytracing.github.io/books/RayTracingInOneWeekend.html) and [book 2](https://raytracing.github.io/books/RayTracingTheNextWeek.html). Written by hand in Odin.

I made it multi-threaded so it renders faster. It divides the render into cells, and every thread takes the next free cell left to render.

Build and usage example (pass a number from 0 to 9 to choose the scene to render):

```
odin build lucyray.odin -file -o:speed
.\lucyray.exe 0 
```
