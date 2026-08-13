const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native = b.option(bool, "native", "Do not use dependencies, use system files instead") orelse false;
    const shared = b.option(bool, "shared", "Build as a shared library") orelse false;

    const include_src = b.option(bool, "include_src", "Add the src/ directory as an include directory") orelse false;

    const use_x11 = b.option(bool, "x11", "Build with X11. Only useful on Linux") orelse true;
    const use_wl = b.option(bool, "wayland", "Build with Wayland. Only useful on Linux") orelse false;

    const use_opengl = b.option(bool, "opengl", "Build with OpenGL; deprecated on MacOS") orelse false;
    const use_gles = b.option(bool, "gles", "Build with GLES; not supported on MacOS") orelse false;
    const use_metal = b.option(bool, "metal", "Build with Metal; only supported on MacOS") orelse false;

    const lib: *std.Build.Step.Compile = b.addLibrary(.{
        .name = "glfw",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = switch (shared) {
            false => .static,
            true => .dynamic,
        },
    });
    lib.root_module.addIncludePath(b.path("include"));
    //if (include_src) lib.addIncludePath(b.path("src"));

    if (shared) lib.root_module.addCMacro("_GLFW_BUILD_DLL", "1");

    lib.installHeadersDirectory(b.path("include/GLFW"), "GLFW", .{});
    if (include_src) {
        lib.installHeadersDirectory(b.path("src/"), "GLFW", .{});
        // To maintain the relative paths inside the files in src/
        lib.installHeadersDirectory(b.path("include/GLFW"), "include/GLFW", .{});
    }
    //
    // Header packaging for easy cross compilation
    //
    if (!native) {
        if (b.lazyDependency("vulkan_headers", .{
            .target = target,
            .optimize = optimize,
        })) |dep| {
            lib.root_module.addIncludePath(dep.path("include"));
        }
        if (target.result.os.tag == .linux) {
            if (b.lazyDependency("x11_headers", .{
                .target = target,
                .optimize = optimize,
            })) |dep| {
                lib.root_module.addSystemIncludePath(dep.path(""));
            }
            if (b.lazyDependency("wayland_headers", .{})) |dep| {
                lib.root_module.addSystemIncludePath(dep.path("wayland"));
                lib.root_module.addSystemIncludePath(dep.path("wayland-protocols"));
            }
        }

        if (target.result.os.tag.isDarwin()) {
            // MacOS: this must be defined for macOS 13.3 and older.
            lib.root_module.addCMacro("__kernel_ptr_semantics", "");

            if (b.lazyDependency("xcode_frameworks", .{
                .target = target,
                .optimize = optimize,
            })) |dep| {
                lib.root_module.addSystemFrameworkPath(dep.path("Frameworks"));
                lib.root_module.addSystemIncludePath(dep.path("include"));
                lib.root_module.addLibraryPath(dep.path("lib"));
            }
        }
    }

    //
    // Source files
    //
    lib.root_module.addCSourceFiles(.{
        .files = &base_sources,
    });
    switch (target.result.os.tag) {
        .windows => {
            lib.root_module.linkSystemLibrary("gdi32", .{});
            lib.root_module.linkSystemLibrary("user32", .{});
            lib.root_module.linkSystemLibrary("shell32", .{});

            if (use_opengl) {
                lib.root_module.linkSystemLibrary("opengl32", .{});
            }

            if (use_gles) {
                lib.root_module.linkSystemLibrary("GLESv3", .{});
            }

            lib.root_module.addCMacro("_GLFW_WIN32", "1");
            lib.root_module.addCSourceFiles(.{
                .files = &windows_sources,
            });
        },
        .macos => {
            // Transitive dependencies, explicit linkage of these works around
            // ziglang/zig#17130
            lib.root_module.linkFramework("CFNetwork", .{});
            lib.root_module.linkFramework("ApplicationServices", .{});
            lib.root_module.linkFramework("ColorSync", .{});
            lib.root_module.linkFramework("CoreText", .{});
            lib.root_module.linkFramework("ImageIO", .{});

            // Direct dependencies
            lib.root_module.linkSystemLibrary("objc", .{});
            lib.root_module.linkFramework("IOKit", .{});
            lib.root_module.linkFramework("CoreFoundation", .{});
            lib.root_module.linkFramework("AppKit", .{});
            lib.root_module.linkFramework("CoreServices", .{});
            lib.root_module.linkFramework("CoreGraphics", .{});
            lib.root_module.linkFramework("Foundation", .{});
            lib.root_module.linkFramework("QuartzCore", .{});

            if (use_metal) {
                lib.root_module.linkFramework("Metal", .{});
            }

            if (use_opengl) {
                lib.root_module.linkFramework("OpenGL", .{});
            }

            lib.root_module.addCMacro("_GLFW_COCOA", "1");
            lib.root_module.addCSourceFiles(.{
                .files = &macos_sources,
            });
        },

        // everything that isn't windows or mac is linux :P
        else => {
            lib.root_module.addCSourceFiles(.{
                .files = &linux_sources,
            });

            if (use_x11) {
                lib.root_module.addCMacro("_GLFW_X11", "1");
                lib.root_module.addCSourceFiles(.{
                    .files = &linux_x11_sources,
                });
            }

            if (use_wl) {
                lib.root_module.addCMacro("_GLFW_WAYLAND", "1");

                lib.root_module.addCSourceFiles(.{
                    .files = &linux_wl_sources,
                    .flags = &.{
                        "-Wno-implicit-function-declaration",
                    },
                });
            }
        },
    }
    b.installArtifact(lib);
}

const base_sources = [_][]const u8{
    "src/context.c",
    "src/egl_context.c",
    "src/init.c",
    "src/input.c",
    "src/monitor.c",
    "src/null_init.c",
    "src/null_joystick.c",
    "src/null_monitor.c",
    "src/null_window.c",
    "src/osmesa_context.c",
    "src/platform.c",
    "src/vulkan.c",
    "src/window.c",
};

const linux_sources = [_][]const u8{
    "src/linux_joystick.c",
    "src/posix_module.c",
    "src/posix_poll.c",
    "src/posix_thread.c",
    "src/posix_time.c",
    "src/xkb_unicode.c",
};

const linux_wl_sources = [_][]const u8{
    "src/wl_init.c",
    "src/wl_monitor.c",
    "src/wl_window.c",
};

const linux_x11_sources = [_][]const u8{
    "src/glx_context.c",
    "src/x11_init.c",
    "src/x11_monitor.c",
    "src/x11_window.c",
};

const windows_sources = [_][]const u8{
    "src/wgl_context.c",
    "src/win32_init.c",
    "src/win32_joystick.c",
    "src/win32_module.c",
    "src/win32_monitor.c",
    "src/win32_thread.c",
    "src/win32_time.c",
    "src/win32_window.c",
};

const macos_sources = [_][]const u8{
    // C sources
    "src/cocoa_time.c",
    "src/posix_module.c",
    "src/posix_thread.c",

    // ObjC sources
    "src/cocoa_init.m",
    "src/cocoa_joystick.m",
    "src/cocoa_monitor.m",
    "src/cocoa_window.m",
    "src/nsgl_context.m",
};
