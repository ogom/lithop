use crate::COMPONENTS;
use magnus::{Error, Ruby};
use std::fmt::Write;

const NUMBER_FORMAT: &[u8] = b"%.9g\0";

fn append_number(output: &mut String, value: f64) -> Result<(), &'static str> {
    if !value.is_finite() {
        return Err("3MF coordinates must be finite");
    }

    let mut buffer = [0_u8; 64];
    let length = unsafe {
        libc::snprintf(
            buffer.as_mut_ptr().cast(),
            buffer.len(),
            NUMBER_FORMAT.as_ptr().cast(),
            value,
        )
    };
    if length < 0 || length as usize >= buffer.len() {
        return Err("could not format a 3MF coordinate");
    }
    let formatted = std::str::from_utf8(&buffer[..length as usize])
        .map_err(|_| "could not format a 3MF coordinate")?;
    output.push_str(formatted);
    Ok(())
}

fn build_vertex_xml(vertices: &[f64], origin: &[f64]) -> Result<String, &'static str> {
    if vertices.len() % COMPONENTS != 0 {
        return Err("3MF vertices must contain XYZ triples");
    }
    if origin.len() != COMPONENTS || origin.iter().any(|value| !value.is_finite()) {
        return Err("3MF origin must contain three finite values");
    }

    let mut output = String::with_capacity((vertices.len() / COMPONENTS) * 72);
    for vertex in vertices.chunks_exact(COMPONENTS) {
        output.push_str("          <vertex x=\"");
        append_number(&mut output, vertex[0] - origin[0])?;
        output.push_str("\" y=\"");
        append_number(&mut output, vertex[1] - origin[1])?;
        output.push_str("\" z=\"");
        append_number(&mut output, vertex[2] - origin[2])?;
        output.push_str("\"/>\n");
    }
    Ok(output)
}

pub(crate) fn build_vertex_records(
    vertices: &[[f64; COMPONENTS]],
    origin: &[f64],
) -> Result<String, &'static str> {
    if origin.len() != COMPONENTS || origin.iter().any(|value| !value.is_finite()) {
        return Err("3MF origin must contain three finite values");
    }
    let mut output = String::with_capacity(vertices.len() * 72);
    for vertex in vertices {
        output.push_str("          <vertex x=\"");
        append_number(&mut output, vertex[0] - origin[0])?;
        output.push_str("\" y=\"");
        append_number(&mut output, vertex[1] - origin[1])?;
        output.push_str("\" z=\"");
        append_number(&mut output, vertex[2] - origin[2])?;
        output.push_str("\"/>\n");
    }
    Ok(output)
}

pub(crate) fn vertex_xml(
    ruby: &Ruby,
    vertices: Vec<f64>,
    origin: Vec<f64>,
) -> Result<String, Error> {
    build_vertex_xml(&vertices, &origin)
        .map_err(|message| Error::new(ruby.exception_arg_error(), message))
}

fn build_triangle_xml(indices: &[usize]) -> Result<String, &'static str> {
    if indices.len() % COMPONENTS != 0 {
        return Err("3MF triangle indices must contain triples");
    }

    let mut output = String::with_capacity((indices.len() / COMPONENTS) * 56);
    for triangle in indices.chunks_exact(COMPONENTS) {
        writeln!(
            output,
            "          <triangle v1=\"{}\" v2=\"{}\" v3=\"{}\"/>",
            triangle[0], triangle[1], triangle[2]
        )
        .map_err(|_| "could not format 3MF triangle indices")?;
    }
    Ok(output)
}

pub(crate) fn build_triangle_records(
    triangles: &[[u32; COMPONENTS]],
) -> Result<String, &'static str> {
    let mut output = String::with_capacity(triangles.len() * 56);
    for triangle in triangles {
        writeln!(
            output,
            "          <triangle v1=\"{}\" v2=\"{}\" v3=\"{}\"/>",
            triangle[0], triangle[1], triangle[2]
        )
        .map_err(|_| "could not format 3MF triangle indices")?;
    }
    Ok(output)
}

pub(crate) fn triangle_xml(ruby: &Ruby, indices: Vec<usize>) -> Result<String, Error> {
    build_triangle_xml(&indices).map_err(|message| Error::new(ruby.exception_arg_error(), message))
}

#[cfg(test)]
mod tests {
    use super::{build_triangle_xml, build_vertex_xml};

    #[test]
    fn formats_vertex_xml_with_ruby_compatible_precision() {
        let xml = build_vertex_xml(&[1.2345678912, 2.0, 3.0], &[1.0, 0.0, 0.5]).unwrap();
        assert_eq!(
            xml,
            "          <vertex x=\"0.234567891\" y=\"2\" z=\"2.5\"/>\n"
        );
    }

    #[test]
    fn formats_triangle_xml() {
        let xml = build_triangle_xml(&[12, 3, 45]).unwrap();
        assert_eq!(xml, "          <triangle v1=\"12\" v2=\"3\" v3=\"45\"/>\n");
    }
}
