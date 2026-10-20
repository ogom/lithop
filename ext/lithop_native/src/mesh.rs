use crate::xml::{build_triangle_records, build_vertex_records};
use crate::COMPONENTS;
use magnus::{Error, Ruby};
use std::cell::RefCell;
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum VertexKey {
    Coordinates([u64; COMPONENTS]),
    Topology(i64),
}

#[derive(Default)]
pub(crate) struct MeshData {
    pub(crate) vertices: Vec<[f64; COMPONENTS]>,
    pub(crate) triangles: Vec<[u32; COMPONENTS]>,
    coordinate_indices: HashMap<[u64; COMPONENTS], u32>,
    topology_indices: HashMap<i64, u32>,
}

#[magnus::wrap(class = "Lithop::Native::MeshBuilder", free_immediately, size)]
pub(crate) struct MeshBuilder(RefCell<MeshData>);

impl MeshBuilder {
    pub(crate) fn new() -> Self {
        Self(RefCell::new(MeshData::default()))
    }

    pub(crate) fn from_data(data: MeshData) -> Self {
        Self(RefCell::new(data))
    }

    pub(crate) fn add_batch(
        ruby: &Ruby,
        rb_self: &Self,
        coordinates: Vec<f64>,
        topology_keys: Vec<i64>,
    ) -> Result<usize, Error> {
        if coordinates.len() % (COMPONENTS * COMPONENTS) != 0 {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF mesh coordinates must contain complete triangles",
            ));
        }
        if topology_keys.len() * COMPONENTS != coordinates.len() {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF mesh topology key count must match its vertices",
            ));
        }
        if coordinates.iter().any(|value| !value.is_finite()) {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF coordinates must be finite",
            ));
        }

        let mut data = rb_self.0.borrow_mut();
        let maximum_vertex_count = data.vertices.len().checked_add(topology_keys.len());
        if maximum_vertex_count.is_none_or(|count| count > u32::MAX as usize) {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF mesh contains too many vertices",
            ));
        }
        for (triangle_coordinates, triangle_keys) in coordinates
            .chunks_exact(COMPONENTS * COMPONENTS)
            .zip(topology_keys.chunks_exact(COMPONENTS))
        {
            let mut triangle = [0; COMPONENTS];
            for vertex_offset in 0..COMPONENTS {
                let start = vertex_offset * COMPONENTS;
                let point = [
                    triangle_coordinates[start],
                    triangle_coordinates[start + 1],
                    triangle_coordinates[start + 2],
                ];
                let key = vertex_key(point, triangle_keys[vertex_offset]);
                triangle[vertex_offset] = index_mesh_vertex(&mut data, point, key);
            }
            data.triangles.push(triangle);
        }
        Ok(data.triangles.len())
    }

    pub(crate) fn vertex_count(&self) -> usize {
        self.0.borrow().vertices.len()
    }
    pub(crate) fn triangle_count(&self) -> usize {
        self.0.borrow().triangles.len()
    }

    pub(crate) fn center(&self) -> Vec<f64> {
        let data = self.0.borrow();
        let mut minimum = [f64::INFINITY; COMPONENTS];
        let mut maximum = [f64::NEG_INFINITY; COMPONENTS];
        for vertex in &data.vertices {
            for axis in 0..COMPONENTS {
                minimum[axis] = minimum[axis].min(vertex[axis]);
                maximum[axis] = maximum[axis].max(vertex[axis]);
            }
        }
        (0..COMPONENTS)
            .map(|axis| (minimum[axis] + maximum[axis]) / 2.0)
            .collect()
    }

    pub(crate) fn vertex_xml(
        ruby: &Ruby,
        rb_self: &Self,
        offset: usize,
        count: usize,
        origin: Vec<f64>,
    ) -> Result<String, Error> {
        let data = rb_self.0.borrow();
        let end = offset.saturating_add(count).min(data.vertices.len());
        if offset > end {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF vertex offset is out of range",
            ));
        }
        build_vertex_records(&data.vertices[offset..end], &origin)
            .map_err(|message| Error::new(ruby.exception_arg_error(), message))
    }

    pub(crate) fn triangle_xml(
        ruby: &Ruby,
        rb_self: &Self,
        offset: usize,
        count: usize,
    ) -> Result<String, Error> {
        let data = rb_self.0.borrow();
        let end = offset.saturating_add(count).min(data.triangles.len());
        if offset > end {
            return Err(Error::new(
                ruby.exception_arg_error(),
                "3MF triangle offset is out of range",
            ));
        }
        build_triangle_records(&data.triangles[offset..end])
            .map_err(|message| Error::new(ruby.exception_arg_error(), message))
    }

    pub(crate) fn memory_bytes(&self) -> usize {
        let data = self.0.borrow();
        data.vertices.capacity() * std::mem::size_of::<[f64; COMPONENTS]>()
            + data.triangles.capacity() * std::mem::size_of::<[u32; COMPONENTS]>()
            + data.coordinate_indices.capacity()
                * (std::mem::size_of::<[u64; COMPONENTS]>() + std::mem::size_of::<u32>())
            + data.topology_indices.capacity()
                * (std::mem::size_of::<i64>() + std::mem::size_of::<u32>())
    }
}

fn vertex_key(point: [f64; COMPONENTS], topology_key: i64) -> VertexKey {
    if topology_key >= 0 {
        VertexKey::Topology(topology_key)
    } else {
        VertexKey::Coordinates(point.map(|value| if value == 0.0 { 0 } else { value.to_bits() }))
    }
}

pub(crate) fn index_mesh_vertex(
    data: &mut MeshData,
    point: [f64; COMPONENTS],
    key: VertexKey,
) -> u32 {
    let existing = match key {
        VertexKey::Coordinates(coordinates) => data.coordinate_indices.get(&coordinates),
        VertexKey::Topology(topology) => data.topology_indices.get(&topology),
    };
    if let Some(index) = existing {
        return *index;
    }
    let index = data.vertices.len() as u32;
    data.vertices.push(point);
    match key {
        VertexKey::Coordinates(coordinates) => {
            data.coordinate_indices.insert(coordinates, index);
        }
        VertexKey::Topology(topology) => {
            data.topology_indices.insert(topology, index);
        }
    }
    index
}
