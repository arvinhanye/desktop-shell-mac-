import Foundation

enum FileDropTracking {
    struct AddedProject: Equatable {
        let id: String
        let name: String
    }

    struct Outcome: Equatable {
        let added: [AddedProject]
        let error: BridgeError?
    }

    static func isFileDrag(changeCountAtMouseDown: Int?, currentChangeCount: Int, hasFileURLs: Bool) -> Bool {
        guard let changeCountAtMouseDown else { return false }
        return changeCountAtMouseDown != currentChangeCount && hasFileURLs
    }

    static func isInDropRegion(mouse: CGPoint, windowFrame: CGRect, regions: [CGRect]) -> Bool {
        HitTesting.isInteractive(mouse: mouse, windowFrame: windowFrame, regions: regions)
    }

    static func dropOutcome(results: [Result<AppConfig.Project, BridgeError>]) -> Outcome {
        var added: [AddedProject] = []
        var firstError: BridgeError?
        for result in results {
            switch result {
            case .success(let project): added.append(AddedProject(id: project.id, name: project.name))
            case .failure(let error): if firstError == nil { firstError = error }
            }
        }
        return Outcome(added: added, error: firstError)
    }
}
