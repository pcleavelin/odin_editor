use futures::executor::block_on;
use wgpu::util::DeviceExt;
use winit::{
    dpi::LogicalSize,
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::WindowBuilder,
};

#[repr(C)]
struct Vertex([f32; 3]);

impl Vertex {
    const fn desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<Self>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[wgpu::VertexAttribute {
                format: wgpu::VertexFormat::Float32x3,
                offset: 0,
                shader_location: 0,
            }],
        }
    }
}

const FULL_QUAD_VERTS: &[Vertex] = &[
    Vertex([-1.0, -1.0, 0.0]),
    Vertex([-1.0, 1.0, 0.0]),
    Vertex([1.0, 1.0, 0.0]),
    //
    Vertex([-1.0, -1.0, 0.0]),
    Vertex([1.0, -1.0, 0.0]),
    Vertex([1.0, 1.0, 0.0]),
];

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
    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[],
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

                window.request_redraw();
            }
            WindowEvent::MouseInput { .. } => window.request_redraw(),
            WindowEvent::CursorMoved { .. } => {
                window.request_redraw();
            }
            WindowEvent::RedrawRequested => {
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
                    rpass.set_vertex_buffer(0, vertex_buffer.slice(..));
                    rpass.draw(0..FULL_QUAD_VERTS.len() as u32, 0..1);
                }

                queue.submit(Some(encoder.finish()));
                frame.present();

                eprintln!("redraw");
            }
            _ => (),
        },
        _ => (),
    })?;

    Ok(())
}
