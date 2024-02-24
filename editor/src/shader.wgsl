struct VertexInput {
    @location(0) position: vec3<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex
fn vs_main(quad: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.color = vec4(1.0, 0.0, 0.0, 1.0);
    out.clip_position = vec4<f32>(quad.position, 1.0);

    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}
