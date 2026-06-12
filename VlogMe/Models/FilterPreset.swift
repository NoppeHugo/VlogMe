import CoreImage
import CoreImage.CIFilterBuiltins

enum FilterPreset: String, CaseIterable, Codable, Identifiable {
    case none, warm, cold, faded, grain, retro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:  return "Aucun"
        case .warm:  return "Chaleureux"
        case .cold:  return "Froid"
        case .faded: return "Délavé"
        case .grain: return "Grain"
        case .retro: return "Rétro"
        }
    }

    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:  return image
        case .warm:  return applyWarm(image)
        case .cold:  return applyCold(image)
        case .faded: return applyFaded(image)
        case .grain: return applyGrain(image)
        case .retro: return applyRetro(image)
        }
    }

    private func applyWarm(_ img: CIImage) -> CIImage {
        let s = CIFilter.sepiaTone()
        s.inputImage = img; s.intensity = 0.18
        let b = s.outputImage ?? img
        let c = CIFilter.colorControls()
        c.inputImage = b; c.saturation = 1.08; c.brightness = 0.02; c.contrast = 1.04
        return c.outputImage ?? b
    }

    private func applyCold(_ img: CIImage) -> CIImage {
        let m = CIFilter.colorMatrix()
        m.inputImage = img
        m.rVector = CIVector(x: 0.92, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: 1.10, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let b = m.outputImage ?? img
        let c = CIFilter.colorControls()
        c.inputImage = b; c.saturation = 0.82; c.brightness = -0.02; c.contrast = 1.05
        return c.outputImage ?? b
    }

    private func applyFaded(_ img: CIImage) -> CIImage {
        let c = CIFilter.colorControls()
        c.inputImage = img; c.saturation = 0.72; c.brightness = 0.04; c.contrast = 0.86
        let b = c.outputImage ?? img
        let m = CIFilter.colorMatrix()
        m.inputImage = b
        m.rVector = CIVector(x: 0.94, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: 0.94, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: 0.90, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: 0.06, y: 0.05, z: 0.07, w: 0)
        return m.outputImage ?? b
    }

    private func applyGrain(_ img: CIImage) -> CIImage {
        let c = CIFilter.colorControls()
        c.inputImage = img; c.saturation = 0.80; c.contrast = 1.08
        let b = c.outputImage ?? img
        let v = CIFilter.vignette()
        v.inputImage = b; v.intensity = 0.6; v.radius = 1.4
        return v.outputImage ?? b
    }

    private func applyRetro(_ img: CIImage) -> CIImage {
        let c = CIFilter.colorControls()
        c.inputImage = img; c.saturation = 0.75; c.brightness = 0.02; c.contrast = 1.18
        let b = c.outputImage ?? img
        let m = CIFilter.colorMatrix()
        m.inputImage = b
        m.rVector = CIVector(x: 1.06, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: 0.86, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: 0.04, y: 0.01, z: 0, w: 0)
        let w = m.outputImage ?? b
        let v = CIFilter.vignette()
        v.inputImage = w; v.intensity = 0.7; v.radius = 1.6
        return v.outputImage ?? w
    }
}
