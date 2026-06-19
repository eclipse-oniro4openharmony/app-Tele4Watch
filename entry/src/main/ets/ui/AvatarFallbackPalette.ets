/**
 * Returns fallback avatar gradient start color for deterministic palette index.
 *
 * @param paletteIndex Deterministic palette index.
 * @returns Resource color used at gradient start.
 */
export function avatarFallbackGradientStartColor(paletteIndex: number): ResourceColor {
  switch (paletteIndex) {
    case 0:
      return $r('app.color.contact_avatar_palette_0_gradient_start');
    case 1:
      return $r('app.color.contact_avatar_palette_1_gradient_start');
    case 2:
      return $r('app.color.contact_avatar_palette_2_gradient_start');
    case 3:
      return $r('app.color.contact_avatar_palette_3_gradient_start');
    case 4:
      return $r('app.color.contact_avatar_palette_4_gradient_start');
    case 5:
      return $r('app.color.contact_avatar_palette_5_gradient_start');
    case 6:
      return $r('app.color.contact_avatar_palette_6_gradient_start');
    default:
      return $r('app.color.contact_avatar_palette_7_gradient_start');
  }
}

/**
 * Returns fallback avatar gradient end color for deterministic palette index.
 *
 * @param paletteIndex Deterministic palette index.
 * @returns Resource color used at gradient end.
 */
export function avatarFallbackGradientEndColor(paletteIndex: number): ResourceColor {
  switch (paletteIndex) {
    case 0:
      return $r('app.color.contact_avatar_palette_0_gradient_end');
    case 1:
      return $r('app.color.contact_avatar_palette_1_gradient_end');
    case 2:
      return $r('app.color.contact_avatar_palette_2_gradient_end');
    case 3:
      return $r('app.color.contact_avatar_palette_3_gradient_end');
    case 4:
      return $r('app.color.contact_avatar_palette_4_gradient_end');
    case 5:
      return $r('app.color.contact_avatar_palette_5_gradient_end');
    case 6:
      return $r('app.color.contact_avatar_palette_6_gradient_end');
    default:
      return $r('app.color.contact_avatar_palette_7_gradient_end');
  }
}
