mod column_mesh;
mod mesh;
mod palette;
mod xml;

use column_mesh::column_mesh;
use magnus::{function, method, prelude::*, Error, Ruby};
use mesh::MeshBuilder;
use palette::palette_indices;
use xml::{triangle_xml, vertex_xml};

pub(crate) const COMPONENTS: usize = 3;

fn extension_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let lithop = ruby.define_module("Lithop")?;
    let native = lithop.define_module("Native")?;
    native.define_singleton_method("palette_indices", function!(palette_indices, 2))?;
    native.define_singleton_method("vertex_xml", function!(vertex_xml, 2))?;
    native.define_singleton_method("triangle_xml", function!(triangle_xml, 1))?;
    native.define_singleton_method("extension_version", function!(extension_version, 0))?;
    native.define_singleton_method("column_mesh", function!(column_mesh, 8))?;
    let mesh_builder = native.define_class("MeshBuilder", ruby.class_object())?;
    mesh_builder.define_singleton_method("new", function!(MeshBuilder::new, 0))?;
    mesh_builder.define_method("add_batch", method!(MeshBuilder::add_batch, 2))?;
    mesh_builder.define_method("vertex_count", method!(MeshBuilder::vertex_count, 0))?;
    mesh_builder.define_method("triangle_count", method!(MeshBuilder::triangle_count, 0))?;
    mesh_builder.define_method("center", method!(MeshBuilder::center, 0))?;
    mesh_builder.define_method("vertex_xml", method!(MeshBuilder::vertex_xml, 3))?;
    mesh_builder.define_method("triangle_xml", method!(MeshBuilder::triangle_xml, 2))?;
    mesh_builder.define_method("memory_bytes", method!(MeshBuilder::memory_bytes, 0))?;
    Ok(())
}
