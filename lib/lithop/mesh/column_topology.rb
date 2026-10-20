# frozen_string_literal: true

module Lithop
  # Finds columns that must become separate shells to remove four-face edge contacts.
  # rubocop:disable-next Metrics/ClassLength
  class ColumnIsolation
    def initialize(model:, intervals:)
      @model = model
      @intervals = intervals
    end

    def groups
      isolated = {}
      each_edge_contact do |endpoints, owners|
        next unless endpoints.all? { |endpoint| merged_at?(endpoint, owners) }

        _layer, row, column = owners.max
        isolated[[row, column]] = true
      end
      isolated.each_key.with_index(1).to_h.freeze
    end

    private

    def each_edge_contact(&)
      each_x_edge_contact(&)
      each_row_edge_contact(&)
      each_z_edge_contact(&)
    end

    def each_x_edge_contact
      @model.columns.times do |column|
        (1...@model.rows).each do |row_boundary|
          upper = interval_at(row_boundary - 1, column)
          lower = interval_at(row_boundary, column)
          contact = touching_layers(upper, lower)
          next unless contact

          z_index, upper_layer, lower_layer = contact
          owners = [[upper_layer, row_boundary - 1, column], [lower_layer, row_boundary, column]]
          yield [[column, row_boundary, z_index], [column + 1, row_boundary, z_index]], owners
        end
      end
    end

    def each_row_edge_contact
      @model.rows.times do |row|
        (1...@model.columns).each do |x_index|
          left = interval_at(row, x_index - 1)
          right = interval_at(row, x_index)
          contact = touching_layers(left, right)
          next unless contact

          z_index, left_layer, right_layer = contact
          owners = [[left_layer, row, x_index - 1], [right_layer, row, x_index]]
          yield [[x_index, row, z_index], [x_index, row + 1, z_index]], owners
        end
      end
    end

    def each_z_edge_contact
      (1...@model.rows).each do |row_boundary|
        (1...@model.columns).each do |x_index|
          columns = [
            [row_boundary - 1, x_index - 1], [row_boundary - 1, x_index],
            [row_boundary, x_index - 1], [row_boundary, x_index]
          ]
          intervals = columns.map { |row, column| interval_at(row, column) }
          [[0, 3, 1, 2], [1, 2, 0, 3]].each do |first, second, lower_bridge, upper_bridge|
            layer = vertical_contact(
              intervals[first], intervals[second], intervals[lower_bridge], intervals[upper_bridge]
            )
            next unless layer

            owners = [first, second].map do |index|
              row, column = columns[index]
              [layer, row, column]
            end
            yield [[x_index, row_boundary, layer], [x_index, row_boundary, layer + 1]], owners
          end
        end
      end
    end

    def vertical_contact(first, second, lower_bridge, upper_bridge)
      return unless first && second && lower_bridge && upper_bridge

      layer = if lower_bridge.last + 1 == upper_bridge.first
                lower_bridge.last
              elsif upper_bridge.last + 1 == lower_bridge.first
                upper_bridge.last
              end
      return unless layer
      return unless [first, second].all? { |interval| interval.first <= layer - 1 && interval.last >= layer + 2 }

      layer
    end

    def merged_at?(endpoint, owners)
      x_index, row_boundary, z_index = endpoint
      incident = [z_index - 1, z_index].product(
        [row_boundary - 1, row_boundary],
        [x_index - 1, x_index]
      ).select { |owner| occupied?(*owner) }
      connected?(owners.first, owners.last, incident)
    end

    def connected?(start, target, incident)
      visited = {}
      pending = [start]
      until pending.empty?
        current = pending.pop
        next if visited[current]
        return true if current == target

        visited[current] = true
        pending.concat(incident.reject do |candidate|
          visited[candidate] || !face_neighbours?(current, candidate)
        end)
      end
      false
    end

    def face_neighbours?(left, right)
      left.zip(right).sum { |a, b| (a - b).abs } == 1
    end

    def touching_layers(first, second)
      return unless first && second
      return [first.last, first.last - 1, second.first] if first.last == second.first

      [second.last, first.first, second.last - 1] if second.last == first.first
    end

    def interval_at(row, column)
      return if row.negative? || column.negative? || row >= @model.rows || column >= @model.columns

      @intervals.fetch((row * @model.columns) + column)
    end

    def occupied?(layer, row, column)
      return false if layer.negative? || row.negative? || column.negative?
      return false if row >= @model.rows || column >= @model.columns

      interval = @intervals.fetch((row * @model.columns) + column)
      interval && layer >= interval.first && layer < interval.last
    end
  end

  # Assigns stable vertex identities after exceptional columns are isolated.
  class ColumnTopology
    Vertex = VoxelTopology::Vertex
    COMPONENT_ROOTS = Array.new(256) do |mask|
      roots = Array.new(8)
      8.times do |start|
        next if mask.nobits?(1 << start) || roots[start]

        component = []
        pending = [start]
        until pending.empty?
          current = pending.pop
          next if component.include?(current)

          component << current
          8.times do |candidate|
            next if mask.nobits?(1 << candidate) || component.include?(candidate)

            pending << candidate if (current ^ candidate).then { |difference| [1, 2, 4].include?(difference) }
          end
        end
        root = component.min
        component.each { |member| roots[member] = root }
      end
      roots.freeze
    end.freeze

    attr_reader :group_ids, :group_count

    def initialize(model:, intervals:)
      @model = model
      @intervals = intervals
      isolated = ColumnIsolation.new(model:, intervals:).groups
      @group_ids = Array.new(model.rows * model.columns, 0)
      isolated.each { |(row, column), group| @group_ids[(row * model.columns) + column] = group }
      @group_count = isolated.length + 1
      @z_count = model.z_boundaries.length
      @mask_cache = {}
      @vertex_cache = {}
    end

    def same_group?(left_row, left_column, right_row, right_column)
      group_at(left_row, left_column) == group_at(right_row, right_column)
    end

    def vertex(x_index, row_boundary, z_index, owner)
      _layer, row, column = owner
      group = group_at(row, column)
      topology = topology_key(x_index, row_boundary, z_index, owner, group)
      @vertex_cache[topology] ||= Vertex.new(
        x: @model.x_boundaries.fetch(x_index),
        y: @model.y_boundaries.last - @model.y_boundaries.fetch(row_boundary),
        z: @model.z_boundaries.fetch(z_index),
        topology:
      )
    end

    def release_cache!
      @mask_cache.clear
      @vertex_cache.clear
    end

    private

    def topology_key(x_index, row_boundary, z_index, owner, group)
      coordinate_key = (((x_index * (@model.rows + 1)) + row_boundary) * @z_count) + z_index
      cache_key = (coordinate_key * @group_count) + group
      mask = @mask_cache[cache_key] ||= occupancy_mask(x_index, row_boundary, z_index, group)
      owner_bit = owner_bit(owner, x_index, row_boundary, z_index)
      component = COMPONENT_ROOTS.fetch(mask).fetch(owner_bit)
      (cache_key * 8) + component
    end

    def occupancy_mask(x_index, row_boundary, z_index, group)
      mask = 0
      2.times do |layer_offset|
        2.times do |row_offset|
          2.times do |column_offset|
            bit = (layer_offset * 4) + (row_offset * 2) + column_offset
            occupied = occupied?(
              z_index - 1 + layer_offset,
              row_boundary - 1 + row_offset,
              x_index - 1 + column_offset,
              group
            )
            mask |= (1 << bit) if occupied
          end
        end
      end
      mask
    end

    def owner_bit(owner, x_index, row_boundary, z_index)
      layer, row, column = owner
      ((layer - z_index + 1) * 4) + ((row - row_boundary + 1) * 2) + (column - x_index + 1)
    end

    def occupied?(layer, row, column, group)
      interval = interval_at(row, column)
      interval && layer >= interval.first && layer < interval.last && group_at(row, column) == group
    end

    def group_at(row, column)
      return 0 if row.negative? || column.negative? || row >= @model.rows || column >= @model.columns

      @group_ids.fetch((row * @model.columns) + column)
    end

    def interval_at(row, column)
      return if row.negative? || column.negative? || row >= @model.rows || column >= @model.columns

      @intervals.fetch((row * @model.columns) + column)
    end
  end
end
