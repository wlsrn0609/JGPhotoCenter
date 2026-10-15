
import UIKit
import Photos
import AVFoundation
import ObjectiveC



public class JGPhotoCenter {
    
    public static let version = "0.1.0"
    
    public enum ContentOption {
        case camera
        case album
    }
    
    public static func show(from targetVC: UIViewController,
                     contentOption: ContentOption,
                     allowsEditing: Bool = false,
                     completion: @MainActor @escaping (UIImage) -> Void) {
        
        self.requestPermission(targetVC: targetVC, contentOption: contentOption) {
            Task { @MainActor in
                let picker = UIImagePickerController()
                picker.modalPresentationStyle = .fullScreen
                picker.allowsEditing = allowsEditing
                picker.sourceType = contentOption == .camera ? .camera : .savedPhotosAlbum
                assignCoordinatorAndPresent(picker, on: targetVC, completion: completion)
            }
        }
    }
    
    @MainActor
    private static func assignCoordinatorAndPresent(_ picker: UIImagePickerController,
                                                    on vc: UIViewController,
                                                    completion: @MainActor @escaping (UIImage) -> Void) {
        let coordinator = JGPickerCoordinator(picker: picker, completion: completion)
        
        // picker가 살아있는 동안 coordinator를 붙잡기
        objc_setAssociatedObject(picker, &JGPickerCoordinator.associationKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        picker.delegate = coordinator
        vc.present(picker, animated: true)
    }
}

@MainActor
private final class JGPickerCoordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    static var associationKey: UInt8 = 0
    private let picker: UIImagePickerController
    private let completion: @MainActor (UIImage) -> Void
    
    init(picker: UIImagePickerController, completion: @MainActor @escaping (UIImage) -> Void) {
        self.picker = picker
        self.completion = completion
        super.init()
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) { [weak self] in
            let key: UIImagePickerController.InfoKey = picker.allowsEditing ? .editedImage : .originalImage
            if let image = info[key] as? UIImage {
                self?.completion(image.fixedOrientation())
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

public extension JGPhotoCenter {
    
    static func requestPermission(targetVC:UIViewController, contentOption : ContentOption, completion: @MainActor @escaping () -> Void) {
        switch contentOption {
        case .camera:
            Self.requestCameraPermission(targetVC: targetVC, completion: completion)
        case .album:
            Self.requestAlbumPermission(targetVC: targetVC, completion: completion)
        }
    }
    
    private static func requestCameraPermission(targetVC: UIViewController, completion: @MainActor @escaping () -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                Task { @MainActor in completion() }
            } else {
                showAlertForDeniedCamera(targetVC: targetVC)
            }
        }
    }
    
    private static func requestAlbumPermission(targetVC: UIViewController, completion: @MainActor @escaping () -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized || status == .limited {
                Task { @MainActor in completion() }
            } else {
                showAlertForDeniedAlbum(targetVC: targetVC)
            }
        }
    }
    
    private static func showAlertForDeniedCamera(targetVC: UIViewController) {
        showPermissionAlert(on: targetVC,
                            title: "카메라 엑세스 권한이 없어요",
                            message: "‘설정’에서 카메라 접근을 허용해 주세요")
    }
    
    private static func showAlertForDeniedAlbum(targetVC: UIViewController) {
        showPermissionAlert(on: targetVC,
                            title: "사진 및 미디어 엑세스 권한이 없어요",
                            message: "‘설정’에서 엑세스 권한을 허용해 주세요")
    }
    
    private static func showPermissionAlert(on vc: UIViewController, title: String, message: String) {
        Task { @MainActor in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "설정", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "취소", style: .cancel))
            vc.present(alert, animated: true)
        }
    }
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}
