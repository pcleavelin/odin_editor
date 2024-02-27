mod editor_core;

use core_graphics::{color_space::CGColorSpace, context::CGContext};
use editor_core::ui::{self, SemanticSize};
use futures::executor::block_on;
use piet_common::{kurbo::Rect, RenderContext, Text, TextLayoutBuilder};
use piet_coregraphics::CoreGraphicsContext;
use wgpu::util::DeviceExt;
use winit::{
    dpi::LogicalSize,
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};

#[repr(C)]
struct Vertex {
    position: [f32; 3],
    tex_coord: [f32; 2],
}

impl Vertex {
    const fn desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<Self>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[
                wgpu::VertexAttribute {
                    format: wgpu::VertexFormat::Float32x3,
                    offset: 0,
                    shader_location: 0,
                },
                wgpu::VertexAttribute {
                    format: wgpu::VertexFormat::Float32x2,
                    // size_of::<[f32; 3]> because the tex coords are right after the vertex
                    // positions
                    offset: std::mem::size_of::<[f32; 3]>() as wgpu::BufferAddress,
                    shader_location: 1,
                },
            ],
        }
    }
}

const FULL_QUAD_VERTS: &[Vertex] = &[
    Vertex {
        position: [-1.0, -1.0, 0.0],
        tex_coord: [0.0, 1.0],
    },
    Vertex {
        position: [-1.0, 1.0, 0.0],
        tex_coord: [0.0, 0.0],
    },
    Vertex {
        position: [1.0, 1.0, 0.0],
        tex_coord: [1.0, 0.0],
    },
    //
    Vertex {
        position: [-1.0, -1.0, 0.0],
        tex_coord: [0.0, 1.0],
    },
    Vertex {
        position: [1.0, -1.0, 0.0],
        tex_coord: [1.0, 1.0],
    },
    Vertex {
        position: [1.0, 1.0, 0.0],
        tex_coord: [1.0, 0.0],
    },
];

struct Texture<'a> {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    sampler: &'a wgpu::Sampler,
    layout: &'a wgpu::BindGroupLayout,
    bind_group: wgpu::BindGroup,

    width: u32,
    height: u32,
}

impl<'a> Texture<'a> {
    const fn desc() -> wgpu::BindGroupLayoutDescriptor<'static> {
        wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        }
    }

    fn create_wgpu_texture(
        device: &wgpu::Device,
        layout: &wgpu::BindGroupLayout,
        sampler: &'a wgpu::Sampler,
        width: u32,
        height: u32,
    ) -> (wgpu::Texture, wgpu::TextureView, wgpu::BindGroup) {
        let texture_size = wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        };
        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: None,
            size: texture_size,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let texture_view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        let texture_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&texture_view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(sampler),
                },
            ],
        });

        (texture, texture_view, texture_bind_group)
    }
    fn new(
        device: &wgpu::Device,
        layout: &'a wgpu::BindGroupLayout,
        sampler: &'a wgpu::Sampler,
        width: u32,
        height: u32,
    ) -> Self {
        let (texture, view, bind_group) =
            Self::create_wgpu_texture(device, layout, sampler, width, height);

        Self {
            texture,
            view,
            layout,
            bind_group,
            sampler,

            width,
            height,
        }
    }

    fn resize(&mut self, device: &wgpu::Device, width: u32, height: u32) {
        self.texture.destroy();

        (self.texture, self.view, self.bind_group) =
            Self::create_wgpu_texture(device, self.layout, self.sampler, width, height);

        self.width = width;
        self.height = height;
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let event_loop = EventLoop::new()?;
    let logical_size = LogicalSize::new(800.0, 600.0);

    let window = WindowBuilder::new()
        .with_title("editor - [now with oxide]")
        .with_inner_size(logical_size)
        .build(&event_loop)?;
    let window_size = window.inner_size();

    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::METAL,
        flags: wgpu::InstanceFlags::default(),
        dx12_shader_compiler: wgpu::Dx12Compiler::default(),
        gles_minor_version: wgpu::Gles3MinorVersion::Automatic,
    });

    let surface = instance.create_surface(&window)?;
    let adapter = block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::LowPower,
        force_fallback_adapter: false,
        compatible_surface: Some(&surface),
    }))
    .ok_or("failed to find an adapter".to_string())?;

    let (device, queue) = block_on(adapter.request_device(
        &wgpu::DeviceDescriptor {
            label: None,
            required_features: wgpu::Features::empty(),
            required_limits: wgpu::Limits::default(),
        },
        None,
    ))
    .map_err(|err| format!("failed to create device {err}"))?;

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(include_str!("shader.wgsl"))),
    });

    let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: None,
        contents: unsafe {
            let len = std::mem::size_of_val(FULL_QUAD_VERTS);
            core::slice::from_raw_parts(FULL_QUAD_VERTS.as_ptr() as *const u8, len)
        },
        usage: wgpu::BufferUsages::VERTEX,
    });

    let sampler = device.create_sampler(&wgpu::SamplerDescriptor::default());
    let texture_layout = device.create_bind_group_layout(&Texture::desc());
    let mut texture = Texture::new(
        &device,
        &texture_layout,
        &sampler,
        window_size.width,
        window_size.height,
    );
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[&texture_layout],
        push_constant_ranges: &[],
    });
    let swapchain_capabilities = surface.get_capabilities(&adapter);
    let swapchain_format = swapchain_capabilities.formats[0];

    let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: "vs_main",
            buffers: &[Vertex::desc()],
        },
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: "fs_main",
            targets: &[Some(swapchain_format.into())],
        }),
        multiview: None,
    });
    let mut config = surface
        .get_default_config(&adapter, window_size.width, window_size.height)
        .unwrap();
    surface.configure(&device, &config);

    let window = &window;
    event_loop.set_control_flow(ControlFlow::Wait);

    let mut cg_context = CGContext::create_bitmap_context(
        None,
        texture.width as usize,
        texture.height as usize,
        8,
        4 * texture.width as usize,
        &CGColorSpace::create_device_rgb(),
        core_graphics::base::kCGImageAlphaPremultipliedLast,
    );

    /*************************/

    let mut cx = ui::Context::new();
    cx.make_node("first child");
    cx._make_node_with_semantic_size(
        "second child",
        [SemanticSize::Fill, SemanticSize::PercentOfParent(50)],
    );
    let key = cx._make_node_with_semantic_size(
        "third child with children",
        [SemanticSize::ChildrenSum, SemanticSize::ChildrenSum],
    );
    cx.push_parent(key);
    {
        cx.make_node("first nested child");
        cx._make_node_with_semantic_size(
            "second nested child",
            [SemanticSize::FitText, SemanticSize::Exact(256)],
        );
        cx.make_node("third nested child");
    }
    cx.pop_parent();
    cx._make_node_with_semantic_size(
        "SEVEN third child",
        [SemanticSize::Fill, SemanticSize::FitText],
    );
    cx.make_node("EIGHT fifth child");

    cx.debug_print();
    cx.update_layout([window_size.width as i32, window_size.height as i32], 0);

    /*************************/

    #[allow(clippy::single_match)]
    event_loop.run(move |event, elwt| match event {
        Event::WindowEvent { event, .. } => match event {
            WindowEvent::CloseRequested => elwt.exit(),
            WindowEvent::DroppedFile(path_buf) => {
                eprintln!("{path_buf:?}");
            }
            WindowEvent::Resized(size) => {
                config.width = size.width;
                config.height = size.height;

                surface.configure(&device, &config);
                texture.resize(&device, config.width, config.height);
                cg_context = CGContext::create_bitmap_context(
                    None,
                    texture.width as usize,
                    texture.height as usize,
                    8,
                    4 * texture.width as usize,
                    &CGColorSpace::create_device_rgb(),
                    core_graphics::base::kCGImageAlphaPremultipliedLast,
                );
                window.request_redraw();
            }
            WindowEvent::MouseInput { .. } => window.request_redraw(),
            WindowEvent::CursorMoved { .. } => {
                window.request_redraw();
            }
            WindowEvent::RedrawRequested => {
                cx.update_layout([texture.width as i32, texture.height as i32], 0);

                let frame = surface
                    .get_current_texture()
                    .expect("failed to acquire next swap chain texture");
                let view = frame
                    .texture
                    .create_view(&wgpu::TextureViewDescriptor::default());
                let mut encoder =
                    device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                {
                    let mut rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                        label: None,
                        color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                            view: &view,
                            resolve_target: None,
                            ops: wgpu::Operations {
                                load: wgpu::LoadOp::Clear(wgpu::Color::GREEN),
                                store: wgpu::StoreOp::Store,
                            },
                        })],
                        depth_stencil_attachment: None,
                        timestamp_writes: None,
                        occlusion_query_set: None,
                    });
                    rpass.set_pipeline(&render_pipeline);
                    rpass.set_bind_group(0, &texture.bind_group, &[]);
                    rpass.set_vertex_buffer(0, vertex_buffer.slice(..));
                    rpass.draw(0..FULL_QUAD_VERTS.len() as u32, 0..1);
                }

                let piet_render = || -> Result<(), Box<dyn std::error::Error>> {
                    {
                        let mut piet_context = CoreGraphicsContext::new_y_up(
                            &mut cg_context,
                            texture.height as f64,
                            None,
                        );

                        piet_context.clear(None, piet_common::Color::BLACK);

                        for node in cx.node_iter() {
                            piet_context.stroke(
                                Rect::new(
                                    node.size.computed_pos[0] as f64,
                                    (node.size.computed_pos[1]) as f64,
                                    (node.size.computed_pos[0] + node.size.computed_size[0]) as f64,
                                    (node.size.computed_pos[1] + node.size.computed_size[1]) as f64,
                                ),
                                &piet_common::Color::WHITE,
                                2.0,
                            );

                            let layout = piet_context
                                .text()
                                .new_text_layout(node.label.clone())
                                .text_color(piet_common::Color::WHITE)
                                .build()
                                .unwrap();
                            piet_context.draw_text(
                                &layout,
                                (
                                    node.size.computed_pos[0] as f64,
                                    node.size.computed_pos[1] as f64,
                                ),
                            );
                        }

                        piet_context.finish()?;
                    }

                    queue.write_texture(
                        wgpu::ImageCopyTexture {
                            texture: &texture.texture,
                            mip_level: 0,
                            origin: wgpu::Origin3d::ZERO,
                            aspect: wgpu::TextureAspect::All,
                        },
                        cg_context.data(),
                        wgpu::ImageDataLayout {
                            offset: 0,
                            bytes_per_row: Some(4 * texture.width),
                            rows_per_image: Some(texture.height),
                        },
                        wgpu::Extent3d {
                            width: texture.width,
                            height: texture.height,
                            depth_or_array_layers: 1,
                        },
                    );

                    Ok(())
                }();

                if let Err(err) = piet_render {
                    eprintln!("failed to render with piet: {err}");
                    elwt.exit();
                }

                queue.submit(Some(encoder.finish()));
                frame.present();
            }
            _ => (),
        },
        _ => (),
    })?;

    Ok(())
}
