import Foundation
import UIKit

func remoteImageSignal(url: String) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard let imageURL = URL(string: url) else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            guard let data, let image = UIImage.decodeImage(from: data) else {
                subscriber.putCompletion()
                return
            }

            subscriber.putNext({ arguments -> DrawingContext? in
                let context = DrawingContext(size: arguments.boundingSize, scale: arguments.scale ?? UIScreen.main.scale, clear: true)
                context?.withFlippedContext { ctx in
                    let drawRect = CGRect(origin: .zero, size: arguments.boundingSize)

                    let cornerRadius = arguments.corners.topLeft.radius
                    if cornerRadius > 0 {
                        let path = UIBezierPath(roundedRect: drawRect, cornerRadius: cornerRadius)
                        ctx.addPath(path.cgPath)
                        ctx.clip()
                    }

                    let imageSize = image.size
                    let fittedSize = imageSize.aspectFilled(arguments.boundingSize)
                    let drawOrigin = CGPoint(
                        x: (arguments.boundingSize.width - fittedSize.width) / 2,
                        y: (arguments.boundingSize.height - fittedSize.height) / 2
                    )

                    if let cgImage = image.cgImage {
                        ctx.draw(cgImage, in: CGRect(origin: drawOrigin, size: fittedSize))
                    }
                }
                return context
            })
            subscriber.putCompletion()
        }
        task.resume()

        return ActionDisposable { task.cancel() }
    }
}

func remoteImageUISignal(url: String) -> Signal<UIImage?, NoError> {
    return Signal { subscriber in
        guard let imageURL = URL(string: url) else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            let image = data.flatMap { UIImage.decodeImage(from: $0) }
            subscriber.putNext(image)
            subscriber.putCompletion()
        }
        task.resume()
        return ActionDisposable { task.cancel() }
    }
}
