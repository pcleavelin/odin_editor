package core

import "core:fmt"
import "core:strings"
import "base:intrinsics"
import ns "core:sys/darwin/foundation"

import "vendor:sdl2/ttf"

foreign import CT "system:CoreText.framework"

@(default_calling_convention = "c", link_prefix="CT")
foreign CT {
    @(link_name="kCTFontURLAttribute") FontURLAttribute: StringRef

    FontCreateWithName :: proc (font_name: StringRef, font_size: ns.Float, _matrix: rawptr) -> FontRef ---
    FontCreateWithFontDescriptor :: proc (font_desc_ref: FontDescriptorRef, font_size: ns.Float, _matrix: rawptr) -> FontRef ---
    FontCopyAttribute :: proc(font_ref: FontRef, attr: StringRef) -> TypeRef ---
}

FontTraitMonoSpace :u32: (1 << 10)

FontRef :: distinct rawptr
FontDescriptorRef :: distinct rawptr

TypeRef :: distinct rawptr
StringRef :: distinct rawptr

@(objc_class="NSFont")
NSFont :: struct {
    using _: ns.Object
}

@(objc_class="NSFontManager")
NSFontManager :: struct {
    using _: ns.Object
}

@(objc_class="NSFontDescriptor")
NSFontDescriptor :: struct {
    using _: ns.Object
}

@(objc_type=NSFont, objc_name="userFixedPitchFontOfSize", objc_is_class_method=true)
NSFont_userFixedPitchFontOfSize :: proc "c" (font_size: ns.Float) -> ^NSFont {
    return intrinsics.objc_send(^NSFont, NSFont, "userFixedPitchFontOfSize:", font_size)
}

@(objc_type=NSFont, objc_name="fontDescriptor")
NSFont_fontDescriptor :: proc "c" (target: ^NSFont) -> ^NSFontDescriptor {
    return intrinsics.objc_send(^NSFontDescriptor, target, "fontDescriptor")
}

@(objc_type=NSFontManager, objc_name="sharedFontManager", objc_is_class_method=true)
NSFontManager_sharedFontManager :: proc "c" () -> ^NSFontManager {
    return intrinsics.objc_send(^NSFontManager, NSFontManager, "sharedFontManager")
}

@(objc_type=NSFontManager, objc_name="availableFontFamilies")
NSFontManager_availableFontFamilies :: proc "c" (target: ^NSFontManager) -> ^ns.Array {
    return intrinsics.objc_send(^ns.Array, target, "availableFontFamilies")
}

@(objc_type=NSFontManager, objc_name="availableMembersOfFontFamily")
NSFontManager_availableMembersOfFontFamily :: proc "c" (target: ^NSFontManager, font_family: ^ns.String) -> ^ns.Array {
    return intrinsics.objc_send(^ns.Array, target, "availableMembersOfFontFamily:", font_family)
}

load_default_system_font_path :: proc(font_height: i32) -> cstring {
    font_class := ns.objc_lookUpClass("NSFont")
    assert(font_class != nil)

    font := NSFont.userFixedPitchFontOfSize(ns.Float(font_height))
    font_desc := font->fontDescriptor()

    font_ref := FontCreateWithFontDescriptor(transmute(FontDescriptorRef)font_desc, ns.Float(font_height), nil)
    assert(font_ref != nil)

    return get_font_ref_file_path(font_ref, font_height)
}

@(private)
get_font_ref_file_path :: proc(font_ref: FontRef, font_height: i32) -> cstring {
    font_url := FontCopyAttribute(font_ref, FontURLAttribute)
    assert(font_url != nil)
    
    url := transmute(^ns.URL)font_url
    url_cstring := url->fileSystemRepresentation()

    return url_cstring
} 

load_system_font_list :: proc(allocator := context.temp_allocator) -> []SystemFont {
    manager := NSFontManager.sharedFontManager()
    assert(manager != nil)

    font_families := manager->availableFontFamilies()
    assert(font_families != nil)

    font_family_count := font_families->count()
    system_fonts := make([]SystemFont, font_family_count, allocator = allocator)
    num_monospace_fonts := 0

    for i in 0..<font_family_count {
        font_family_name := font_families->objectAs(i, ^ns.String)
        assert(font_family_name != nil)

        font_members := manager->availableMembersOfFontFamily(font_family_name)

        if font_members == nil {
            continue
        }

        for j in 0..<font_members->count() {
            font_attributes := font_members->objectAs(j, ^ns.Array)
            assert(font_attributes != nil)

            font_name := font_attributes->objectAs(0, ^ns.String);
            font_style := font_attributes->objectAs(1, ^ns.String);
            // font_weight := font_attributes->objectAs(2, ^ns.Number);
            font_trait_mask := font_attributes->objectAs(3, ^ns.Number)->u32Value();

            if (font_trait_mask & FontTraitMonoSpace) > 0 {
                font_ref := FontCreateWithName(transmute(StringRef)font_name, ns.Float(16.0), nil)
                font_file_path := get_font_ref_file_path(font_ref, 16)

                system_fonts[num_monospace_fonts] = SystemFont {
                    display_name = fmt.aprintf("%v - %v", font_family_name->odinString(), font_style->odinString(), allocator = allocator),
                    file_path = font_file_path,
                }

                num_monospace_fonts += 1
            }
        }
    }

    return system_fonts[0:num_monospace_fonts]
}
