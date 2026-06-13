import SwiftUI
import MediaPlayer

struct MusicPickerView: UIViewControllerRepresentable {

    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.delegate = context.coordinator
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.prompt = "Choisir une musique de fond"
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            let url = mediaItemCollection.items.first?.assetURL
            mediaPicker.dismiss(animated: true) { self.onPick(url) }
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            mediaPicker.dismiss(animated: true) { self.onPick(nil) }
        }
    }
}
