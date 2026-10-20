use crate::COMPONENTS;
use magnus::{Error, Ruby};

fn select_palette_indices(cmys: &[f64], coverages: &[f64]) -> Result<Vec<usize>, &'static str> {
    if cmys.len() % COMPONENTS != 0 {
        return Err("CMY values must contain triples");
    }
    if coverages.is_empty() || coverages.len() % COMPONENTS != 0 {
        return Err("recipe coverage must contain triples");
    }
    if cmys
        .iter()
        .any(|value| !value.is_finite() || !(0.0..=1.0).contains(value))
    {
        return Err("CMY values must be finite values between zero and one");
    }

    let recipes: Vec<&[f64]> = coverages.chunks_exact(COMPONENTS).collect();
    let mut indices = Vec::with_capacity(cmys.len() / COMPONENTS);
    for target in cmys.chunks_exact(COMPONENTS) {
        let mut best_index = 0;
        let mut best_distance = f64::INFINITY;
        for (index, coverage) in recipes.iter().enumerate() {
            let cyan = coverage[0] - target[0];
            let magenta = coverage[1] - target[1];
            let yellow = coverage[2] - target[2];
            let distance = (cyan * cyan) + (magenta * magenta) + (yellow * yellow);
            if distance < best_distance {
                best_index = index;
                best_distance = distance;
            }
        }
        indices.push(best_index);
    }
    Ok(indices)
}

pub(crate) fn palette_indices(
    ruby: &Ruby,
    cmys: Vec<f64>,
    coverages: Vec<f64>,
) -> Result<Vec<usize>, Error> {
    select_palette_indices(&cmys, &coverages)
        .map_err(|message| Error::new(ruby.exception_arg_error(), message))
}

#[cfg(test)]
mod tests {
    use super::select_palette_indices;

    #[test]
    fn selects_the_first_recipe_at_equal_distance() {
        let indices =
            select_palette_indices(&[0.5, 0.0, 0.0], &[0.0, 0.0, 0.0, 1.0, 0.0, 0.0]).unwrap();
        assert_eq!(indices, vec![0]);
    }

    #[test]
    fn selects_multiple_samples_in_one_call() {
        let indices = select_palette_indices(
            &[0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
            &[0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        )
        .unwrap();
        assert_eq!(indices, vec![0, 1]);
    }
}
