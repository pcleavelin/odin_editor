package core

import "core:fmt"
import "base:intrinsics"
import ns "core:sys/darwin/foundation"

import "vendor:sdl2/ttf"

foreign import CT "system:CoreText.framework"

@(default_calling_convention = "c", link_prefix="CT")
foreign CT {
    @(link_name="kCTFontURLAttribute") FontURLAttribute: StringRef
    
    FontCreateWithFontDescriptor :: proc (font_desc_ref: FontDescriptorRef, font_size: ns.Float, _matrix: rawptr) -> FontRef ---
    FontCopyAttribute :: proc(font_ref: FontRef, attr: StringRef) -> TypeRef ---
}

FontRef :: distinct rawptr
FontDescriptorRef :: distinct rawptr

TypeRef :: distinct rawptr
StringRef :: distinct rawptr

@(objc_class="NSFont")
NSFont :: struct {
    using _: ns.Object
}

@(objc_class="NSFontDescriptor")
NSFontDescriptor :: struct {
    using _: ns.Object
}

@(objc_type=NSFont, objc_name="userFixedPitchFontOfSize", objc_is_class_method=true)
NSFont_userFixedPitchFontOfSize :: proc "c" (target: ^intrinsics.objc_object, font_size: ns.Float) -> ^NSFont {
    return intrinsics.objc_send(^NSFont, NSFont, "userFixedPitchFontOfSize:", font_size)
}

@(objc_type=NSFont, objc_name="fontDescriptor")
NSFont_fontDescriptor :: proc "c" (target: ^NSFont) -> ^NSFontDescriptor {
    return intrinsics.objc_send(^NSFontDescriptor, target, "fontDescriptor")
}

@(objc_type=NSFont, objc_name="displayName")
NSFont_displayName :: proc "c" (self: ^NSFont) -> ^ns.String {
    return intrinsics.objc_send(^ns.String, self, "displayName")
}

load_default_system_font_path :: proc(font_height: i32) -> cstring {
    font_class := ns.objc_lookUpClass("NSFont")
    assert(font_class != nil)
    
    font := NSFont.userFixedPitchFontOfSize(nil, ns.Float(font_height))
    font_desc := font->fontDescriptor()

    font_ref := FontCreateWithFontDescriptor(transmute(FontDescriptorRef)font_desc, ns.Float(font_height), nil)
    assert(font_ref != nil)

    font_url := FontCopyAttribute(font_ref, FontURLAttribute)
    assert(font_url != nil)
    
    url := transmute(^ns.URL)font_url
    url_cstring := url->fileSystemRepresentation()

    return url_cstring
}
