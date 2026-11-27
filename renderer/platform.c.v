module renderer

import witty_macos as macos
$if renderer_opengl ? && renderer_metal ? {
	$compile_error('renderer configuration must select one backend')
}

// renderer.zig selects a single graphics implementation from build options.
// The pinned WebGL source is empty; it has no native renderer API to instantiate.
$if renderer_webgl ?|| ( wasm32 && !renderer_opengl ?&& !renderer_metal ?) {
	$compile_error('pinned Ghostty WebGL has no renderer implementation; use VT/font-only wasm exports')
}

$if renderer_opengl ? {
	pub type GraphicsAPI = OpenGLAPI
	pub type GraphicsShaders = GLShaders
	pub type GraphicsFrameState = GLFrameState
	pub type GraphicsTexture = GLTexture
} $else $if renderer_metal ?|| macos || ios {
	pub type GraphicsAPI = MetalAPI
	pub type GraphicsShaders = MetalShaders
	pub type GraphicsFrameState = MetalFrameState
	pub type GraphicsTexture = MetalTexture
} $else {
	pub type GraphicsAPI = OpenGLAPI
	pub type GraphicsShaders = GLShaders
	pub type GraphicsFrameState = GLFrameState
	pub type GraphicsTexture = GLTexture
}

$if renderer_metal ?&& !macos && !ios {
	$compile_error('Metal requires a Darwin target')
}

// These source types follow the OS, independently of the graphics backend.
$if macos {
	pub type DisplayLink = macos.CVDisplayLink
} $else {
	pub struct DisplayLink {}
}
$if macos || ios {
	pub type AutoreleasePool = macos.AutoreleasePool
} $else {
	pub struct AutoreleasePool {}
}
