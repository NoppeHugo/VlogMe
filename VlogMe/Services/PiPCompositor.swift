import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Metal

/// Incruste l'image d'une caméra (`overlay`) dans le coin supérieur gauche de l'autre (`main`)
/// pour le mode Duo : l'incrustation occupe `windowFraction` de la largeur et de la hauteur,
/// avec des coins arrondis.
///
/// Utilisé sur la queue vidéo, à la cadence de capture — le rendu passe par Metal.
final class PiPCompositor {

    /// Fraction de la largeur/hauteur du canevas occupée par l'incrustation.
    /// Partagée avec la preview live (`CameraPreviewLayerView`) pour que ce que
    /// l'on voit à l'écran corresponde à la vidéo enregistrée.
    static let windowFraction: CGFloat = 0.30

    private let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext()
    }()

    private var pool: CVPixelBufferPool?
    private var poolWidth  = 0
    private var poolHeight = 0
    private var cachedMask: CIImage?
    private var cachedMaskKey = ""

    /// Retourne une nouvelle frame composée, ou nil si le rendu échoue
    /// (dans ce cas l'appelant écrit la frame principale telle quelle).
    func compose(main: CVPixelBuffer, overlay: CVPixelBuffer) -> CVPixelBuffer? {
        let width  = CVPixelBufferGetWidth(main)
        let height = CVPixelBufferGetHeight(main)
        guard let output = makeBuffer(width: width, height: height) else { return nil }

        let mainImage = CIImage(cvPixelBuffer: main)
        var overlayImage = CIImage(cvPixelBuffer: overlay)

        // Cadre de l'incrustation : marge ~3,5 %, coin haut-gauche
        // (le repère Core Image a l'origine en bas à gauche).
        let pipWidth  = CGFloat(width)  * Self.windowFraction
        let pipHeight = CGFloat(height) * Self.windowFraction
        let margin    = CGFloat(width)  * 0.035
        let pipRect = CGRect(
            x: margin,
            y: CGFloat(height) - margin - pipHeight,
            width: pipWidth,
            height: pipHeight
        )

        // Remplit le cadre (aspect fill), centre, puis rogne.
        let scale = max(pipWidth / overlayImage.extent.width, pipHeight / overlayImage.extent.height)
        overlayImage = overlayImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = pipRect.minX - (overlayImage.extent.width  - pipWidth)  / 2 - overlayImage.extent.minX
        let dy = pipRect.minY - (overlayImage.extent.height - pipHeight) / 2 - overlayImage.extent.minY
        overlayImage = overlayImage
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: pipRect)

        let composed: CIImage
        if let mask = roundedMask(rect: pipRect, canvasWidth: width, canvasHeight: height) {
            let blend = CIFilter.blendWithMask()
            blend.inputImage      = overlayImage
            blend.backgroundImage = mainImage
            blend.maskImage       = mask
            composed = blend.outputImage ?? overlayImage.composited(over: mainImage)
        } else {
            composed = overlayImage.composited(over: mainImage)
        }

        context.render(
            composed.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)),
            to: output
        )
        return output
    }

    // MARK: - Privé

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolWidth != width || poolHeight != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(
                nil,
                [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
                attributes as CFDictionary,
                &newPool
            )
            pool = newPool
            poolWidth = width
            poolHeight = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    /// Masque niveaux de gris (blanc = incrustation) couvrant tout le canevas,
    /// généré une fois puis mis en cache tant que la géométrie ne change pas.
    private func roundedMask(rect: CGRect, canvasWidth: Int, canvasHeight: Int) -> CIImage? {
        let key = "\(canvasWidth)x\(canvasHeight)-\(Int(rect.minX)),\(Int(rect.minY))-\(Int(rect.width))x\(Int(rect.height))"
        if key == cachedMaskKey, let cachedMask { return cachedMask }

        guard let cgContext = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        cgContext.setFillColor(CGColor(gray: 0, alpha: 1))
        cgContext.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
        let radius = rect.width * 0.06
        cgContext.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        cgContext.fillPath()

        guard let cgImage = cgContext.makeImage() else { return nil }
        let mask = CIImage(cgImage: cgImage)
        cachedMask = mask
        cachedMaskKey = key
        return mask
    }
}
