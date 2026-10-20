use crate::mesh::{index_mesh_vertex, MeshBuilder, MeshData, VertexKey};
use crate::COMPONENTS;
use magnus::{Error, Ruby};

struct ColumnMeshInput<'a> {
    columns: usize,
    rows: usize,
    x_boundaries: &'a [f64],
    y_boundaries: &'a [f64],
    z_boundaries: &'a [f64],
    intervals: Vec<Option<(usize, usize)>>,
    group_ids: &'a [usize],
    group_count: usize,
}

impl ColumnMeshInput<'_> {
    fn interval_at(&self, row: isize, column: isize) -> Option<(usize, usize)> {
        if row < 0 || column < 0 || row as usize >= self.rows || column as usize >= self.columns {
            return None;
        }
        self.intervals[row as usize * self.columns + column as usize]
    }

    fn group_at(&self, row: isize, column: isize) -> usize {
        if row < 0 || column < 0 || row as usize >= self.rows || column as usize >= self.columns {
            return 0;
        }
        self.group_ids[row as usize * self.columns + column as usize]
    }

    fn grouped_interval(
        &self,
        row: usize,
        column: usize,
        neighbour_row: isize,
        neighbour_column: isize,
    ) -> Option<(usize, usize)> {
        if self.group_at(row as isize, column as isize)
            != self.group_at(neighbour_row, neighbour_column)
        {
            return None;
        }
        self.interval_at(neighbour_row, neighbour_column)
    }

    fn occupied(&self, layer: isize, row: isize, column: isize, group: usize) -> bool {
        if layer < 0 || self.group_at(row, column) != group {
            return false;
        }
        self.interval_at(row, column)
            .is_some_and(|(bottom, top)| layer as usize >= bottom && (layer as usize) < top)
    }
}

pub(crate) fn column_mesh(
    ruby: &Ruby,
    columns: usize,
    rows: usize,
    x_boundaries: Vec<f64>,
    y_boundaries: Vec<f64>,
    z_boundaries: Vec<f64>,
    raw_intervals: Vec<i64>,
    group_ids: Vec<usize>,
    group_count: usize,
) -> Result<MeshBuilder, Error> {
    let expected_cells = columns.saturating_mul(rows);
    let valid = columns > 0
        && rows > 0
        && x_boundaries.len() == columns + 1
        && y_boundaries.len() == rows + 1
        && z_boundaries.len() >= 2
        && raw_intervals.len() == expected_cells * 2
        && group_ids.len() == expected_cells
        && group_count > 0
        && x_boundaries.iter().all(|value| value.is_finite())
        && y_boundaries.iter().all(|value| value.is_finite())
        && z_boundaries.iter().all(|value| value.is_finite());
    if !valid {
        return Err(Error::new(
            ruby.exception_arg_error(),
            "invalid native column mesh input",
        ));
    }
    let maximum_vertices_per_cell =
        8_usize.saturating_add(16_usize.saturating_mul(z_boundaries.len().saturating_sub(1)));
    if expected_cells.saturating_mul(maximum_vertices_per_cell) > u32::MAX as usize {
        return Err(Error::new(
            ruby.exception_arg_error(),
            "native column mesh contains too many vertices",
        ));
    }

    let intervals = raw_intervals
        .chunks_exact(2)
        .map(|pair| match pair {
            [-1, -1] => Ok(None),
            [bottom, top] if *bottom >= 0 && *top > *bottom && *top < z_boundaries.len() as i64 => {
                Ok(Some((*bottom as usize, *top as usize)))
            }
            _ => Err(Error::new(
                ruby.exception_arg_error(),
                "invalid native column interval",
            )),
        })
        .collect::<Result<Vec<_>, _>>()?;
    let input = ColumnMeshInput {
        columns,
        rows,
        x_boundaries: &x_boundaries,
        y_boundaries: &y_boundaries,
        z_boundaries: &z_boundaries,
        intervals,
        group_ids: &group_ids,
        group_count,
    };
    let mut data = MeshData::default();
    data.triangles.reserve_exact(column_triangle_count(&input));
    for row in 0..rows {
        for column in 0..columns {
            let Some(current) = input.interval_at(row as isize, column as isize) else {
                continue;
            };
            emit_column_caps(&mut data, &input, row, column, current);
            emit_column_sides(&mut data, &input, row, column, current);
        }
    }
    Ok(MeshBuilder::from_data(data))
}

type ColumnOwner = (usize, usize, usize);

fn column_triangle_count(input: &ColumnMeshInput<'_>) -> usize {
    let mut count = 0;
    for row in 0..input.rows {
        for column in 0..input.columns {
            let Some(current) = input.interval_at(row as isize, column as isize) else {
                continue;
            };
            count += 4;
            count += 2 * [
                (row as isize, column as isize - 1),
                (row as isize, column as isize + 1),
                (row as isize + 1, column as isize),
                (row as isize - 1, column as isize),
            ]
            .into_iter()
            .map(|(neighbour_row, neighbour_column)| {
                exposed_layer_count(
                    current,
                    input.grouped_interval(row, column, neighbour_row, neighbour_column),
                )
            })
            .sum::<usize>();
        }
    }
    count
}

fn emit_column_caps(
    data: &mut MeshData,
    input: &ColumnMeshInput<'_>,
    row: usize,
    column: usize,
    current: (usize, usize),
) {
    let (bottom, top) = current;
    let bottom_owner = (bottom, row, column);
    let top_owner = (top - 1, row, column);
    emit_column_quad(
        data,
        [
            column_vertex(input, column, row + 1, bottom, bottom_owner),
            column_vertex(input, column, row, bottom, bottom_owner),
            column_vertex(input, column + 1, row, bottom, bottom_owner),
            column_vertex(input, column + 1, row + 1, bottom, bottom_owner),
        ],
    );
    emit_column_quad(
        data,
        [
            column_vertex(input, column, row + 1, top, top_owner),
            column_vertex(input, column + 1, row + 1, top, top_owner),
            column_vertex(input, column + 1, row, top, top_owner),
            column_vertex(input, column, row, top, top_owner),
        ],
    );
}

fn emit_column_sides(
    data: &mut MeshData,
    input: &ColumnMeshInput<'_>,
    row: usize,
    column: usize,
    current: (usize, usize),
) {
    for layer in exposed_layers(
        current,
        input.grouped_interval(row, column, row as isize, column as isize - 1),
    ) {
        let owner = (layer, row, column);
        emit_column_quad(
            data,
            [
                column_vertex(input, column, row + 1, layer, owner),
                column_vertex(input, column, row + 1, layer + 1, owner),
                column_vertex(input, column, row, layer + 1, owner),
                column_vertex(input, column, row, layer, owner),
            ],
        );
    }
    for layer in exposed_layers(
        current,
        input.grouped_interval(row, column, row as isize, column as isize + 1),
    ) {
        let owner = (layer, row, column);
        emit_column_quad(
            data,
            [
                column_vertex(input, column + 1, row + 1, layer, owner),
                column_vertex(input, column + 1, row, layer, owner),
                column_vertex(input, column + 1, row, layer + 1, owner),
                column_vertex(input, column + 1, row + 1, layer + 1, owner),
            ],
        );
    }
    for layer in exposed_layers(
        current,
        input.grouped_interval(row, column, row as isize + 1, column as isize),
    ) {
        let owner = (layer, row, column);
        emit_column_quad(
            data,
            [
                column_vertex(input, column, row + 1, layer, owner),
                column_vertex(input, column + 1, row + 1, layer, owner),
                column_vertex(input, column + 1, row + 1, layer + 1, owner),
                column_vertex(input, column, row + 1, layer + 1, owner),
            ],
        );
    }
    for layer in exposed_layers(
        current,
        input.grouped_interval(row, column, row as isize - 1, column as isize),
    ) {
        let owner = (layer, row, column);
        emit_column_quad(
            data,
            [
                column_vertex(input, column, row, layer, owner),
                column_vertex(input, column, row, layer + 1, owner),
                column_vertex(input, column + 1, row, layer + 1, owner),
                column_vertex(input, column + 1, row, layer, owner),
            ],
        );
    }
}

fn exposed_layers(current: (usize, usize), neighbour: Option<(usize, usize)>) -> Vec<usize> {
    let (bottom, top) = current;
    let Some((neighbour_bottom, neighbour_top)) = neighbour else {
        return (bottom..top).collect();
    };
    if neighbour_top <= bottom || neighbour_bottom >= top {
        return (bottom..top).collect();
    }
    let mut layers = Vec::new();
    if neighbour_bottom > bottom {
        layers.extend(bottom..top.min(neighbour_bottom));
    }
    if neighbour_top < top {
        layers.extend(bottom.max(neighbour_top)..top);
    }
    layers
}

fn exposed_layer_count(current: (usize, usize), neighbour: Option<(usize, usize)>) -> usize {
    let (bottom, top) = current;
    let Some((neighbour_bottom, neighbour_top)) = neighbour else {
        return top - bottom;
    };
    if neighbour_top <= bottom || neighbour_bottom >= top {
        return top - bottom;
    }
    neighbour_bottom.saturating_sub(bottom).min(top - bottom)
        + top.saturating_sub(neighbour_top).min(top - bottom)
}

fn column_vertex(
    input: &ColumnMeshInput<'_>,
    x_index: usize,
    row_boundary: usize,
    z_index: usize,
    owner: ColumnOwner,
) -> ([f64; COMPONENTS], VertexKey) {
    let (_, owner_row, owner_column) = owner;
    let group = input.group_at(owner_row as isize, owner_column as isize);
    let coordinate_key =
        ((x_index * (input.rows + 1) + row_boundary) * input.z_boundaries.len()) + z_index;
    let cache_key = coordinate_key * input.group_count + group;
    let mask = occupancy_mask(input, x_index, row_boundary, z_index, group);
    let owner_bit = owner_bit(owner, x_index, row_boundary, z_index);
    let component = component_root(mask, owner_bit);
    let topology = cache_key * 8 + component;
    let point = [
        input.x_boundaries[x_index],
        input.y_boundaries[input.y_boundaries.len() - 1] - input.y_boundaries[row_boundary],
        input.z_boundaries[z_index],
    ];
    (point, VertexKey::Topology(topology as i64))
}

fn occupancy_mask(
    input: &ColumnMeshInput<'_>,
    x_index: usize,
    row_boundary: usize,
    z_index: usize,
    group: usize,
) -> u8 {
    let mut mask = 0;
    for layer_offset in 0..2 {
        for row_offset in 0..2 {
            for column_offset in 0..2 {
                let bit = layer_offset * 4 + row_offset * 2 + column_offset;
                if input.occupied(
                    z_index as isize - 1 + layer_offset as isize,
                    row_boundary as isize - 1 + row_offset as isize,
                    x_index as isize - 1 + column_offset as isize,
                    group,
                ) {
                    mask |= 1 << bit;
                }
            }
        }
    }
    mask
}

fn owner_bit(owner: ColumnOwner, x_index: usize, row_boundary: usize, z_index: usize) -> usize {
    let (layer, row, column) = owner;
    ((layer as isize - z_index as isize + 1) * 4
        + (row as isize - row_boundary as isize + 1) * 2
        + column as isize
        - x_index as isize
        + 1) as usize
}

fn component_root(mask: u8, start: usize) -> usize {
    let mut visited = [false; 8];
    let mut pending = [0; 8];
    pending[0] = start;
    let mut pending_count = 1;
    visited[start] = true;
    let mut root = start;
    while pending_count > 0 {
        pending_count -= 1;
        let current = pending[pending_count];
        root = root.min(current);
        for candidate in 0..8 {
            let difference = current ^ candidate;
            if !visited[candidate]
                && mask & (1 << candidate) != 0
                && matches!(difference, 1 | 2 | 4)
            {
                visited[candidate] = true;
                pending[pending_count] = candidate;
                pending_count += 1;
            }
        }
    }
    root
}

fn emit_column_quad(data: &mut MeshData, vertices: [([f64; COMPONENTS], VertexKey); 4]) {
    let indices = vertices.map(|(point, key)| index_mesh_vertex(data, point, key));
    data.triangles.push([indices[0], indices[1], indices[2]]);
    data.triangles.push([indices[0], indices[2], indices[3]]);
}

#[cfg(test)]
mod tests {
    use super::component_root;

    #[test]
    fn finds_face_connected_voxel_components_without_joining_diagonals() {
        assert_eq!(component_root(0b0000_0011, 1), 0);
        assert_eq!(component_root(0b1000_0001, 7), 7);
    }
}
