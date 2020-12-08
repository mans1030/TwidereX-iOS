//
//  DrawerSidebarAnimatedTransitioning.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-11-9.
//  Copyright © 2020 Twidere. All rights reserved.
//

import UIKit
import CommonOSLog

final class DrawerSidebarAnimatedTransitioning: ViewControllerAnimatedTransitioning {

    private var animator: UIViewPropertyAnimator?
    let screenEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer
    let panGestureRecognizer: UIPanGestureRecognizer
    
    init(
        operation: UINavigationController.Operation,
        screenEdgePanGestureRecognizer: UIScreenEdgePanGestureRecognizer,
        panGestureRecognizer: UIPanGestureRecognizer
    ) {
        self.screenEdgePanGestureRecognizer = screenEdgePanGestureRecognizer
        self.panGestureRecognizer = panGestureRecognizer
        super.init(operation: operation)
    }
    
    deinit {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s:", ((#file as NSString).lastPathComponent), #line, #function)
    }
    
}

// MARK: - UIViewControllerAnimatedTransitioning
extension DrawerSidebarAnimatedTransitioning {
    
    override func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        super.animateTransition(using: transitionContext)
        
        switch operation {
        case .push:     pushTransition(using: transitionContext).startAnimation()
        case .pop:      popTransition(using: transitionContext).startAnimation()
        default:        return
        }
    }
    
    private func pushTransition(using transitionContext: UIViewControllerContextTransitioning, curve: UIView.AnimationCurve = .easeInOut) -> UIViewPropertyAnimator {
        guard let toVC = transitionContext.viewController(forKey: .to) as? DrawerSidebarViewController,
              let toView = transitionContext.view(forKey: .to),
              let fromView = transitionContext.view(forKey: .from) else {
            fatalError()
        }

        let transform: CGAffineTransform = {
            switch UIApplication.shared.userInterfaceLayoutDirection {
            case .rightToLeft:
                return CGAffineTransform(translationX: toView.frame.width, y: 0)
            default:
                return CGAffineTransform(translationX: -toView.frame.width, y: 0)
            }
        }()
        transitionContext.containerView.addSubview(toView)
        toView.transform = transform
        fromView.transform = .identity
        
        // fix custom presention container cause layout along with animation issue
        UIView.performWithoutAnimation {
            toView.setNeedsLayout()
            toView.layoutIfNeeded()
        }
        
        let separatorLine = UIView.separatorLine
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        transitionContext.containerView.addSubview(separatorLine)
        NSLayoutConstraint.activate([
            separatorLine.topAnchor.constraint(equalTo: toView.topAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: toView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: toView.bottomAnchor),
            separatorLine.widthAnchor.constraint(equalToConstant: UIView.separatorLineHeight(of: transitionContext.containerView)),
        ])
        separatorLine.transform = transform
        separatorLine.isUserInteractionEnabled = false
                
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), curve: curve)
        
        animator.addAnimations {
            toView.transform = .identity
            separatorLine.transform = .identity
            fromView.transform = transform.inverted()
        }
        
        animator.addCompletion { position in
            if transitionContext.transitionWasCancelled {
                toView.removeFromSuperview()
            }
            separatorLine.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
        
        return animator
    }
    
    private func popTransition(using transitionContext: UIViewControllerContextTransitioning, curve: UIView.AnimationCurve = .easeInOut) -> UIViewPropertyAnimator {
        guard let fromVC = transitionContext.viewController(forKey: .from) as? DrawerSidebarViewController,
              let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            fatalError()
        }

        transitionContext.containerView.addSubview(toView)
        transitionContext.containerView.bringSubviewToFront(fromView)

        let transform: CGAffineTransform = {
            switch UIApplication.shared.userInterfaceLayoutDirection {
            case .rightToLeft:
                return CGAffineTransform(translationX: fromView.frame.width, y: 0)
            default:
                return CGAffineTransform(translationX: -fromView.frame.width, y: 0)
            }
        }()
        fromView.transform = .identity
        
        let separatorLine = UIView.separatorLine
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        transitionContext.containerView.addSubview(separatorLine)
        NSLayoutConstraint.activate([
            separatorLine.topAnchor.constraint(equalTo: fromView.topAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: fromView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: fromView.bottomAnchor),
            separatorLine.widthAnchor.constraint(equalToConstant: UIView.separatorLineHeight(of: transitionContext.containerView)),
        ])
        separatorLine.isUserInteractionEnabled = false
        
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), curve: curve)
        
        animator.addAnimations {
            fromView.transform = transform
            separatorLine.transform = transform
            toView.transform = .identity
        }
        
        animator.addCompletion { position in
            if transitionContext.transitionWasCancelled {
                toView.removeFromSuperview()
            }
            separatorLine.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
        
        return animator
    }
    
}


// MARK: - UIViewControllerInteractiveTransitioning
extension DrawerSidebarAnimatedTransitioning {
    
    override func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        super.startInteractiveTransition(transitionContext)
        
        switch operation {
        case .push:
            animator = pushTransition(using: transitionContext, curve: .linear)
            screenEdgePanGestureRecognizer.addTarget(self, action: #selector(DrawerSidebarAnimatedTransitioning.presentPan(_:)))
            
        case .pop:
            animator = popTransition(using: transitionContext, curve: .linear)
            panGestureRecognizer.addTarget(self, action: #selector(DrawerSidebarAnimatedTransitioning.dismisslPan(_:)))
            
        default:
            return
        }
        
        // fix began event not trigger issue
        animator?.pauseAnimation()
        transitionContext.pauseInteractiveTransition()
    }
    
    @objc private func presentPan(_ sender: UIPanGestureRecognizer) {
        guard let animator = animator else { return }
        switch sender.state {
        case .began:
            animator.pauseAnimation()
            transitionContext.pauseInteractiveTransition()
        case .changed:
            let translation = sender.translation(in: transitionContext.containerView)
            let width = transitionContext.view(forKey: .to)?.bounds.width ?? transitionContext.containerView.bounds.width
            let direction: CGFloat = UIApplication.shared.userInterfaceLayoutDirection == .leftToRight ? 1.0 : -1.0
            let percent = animator.fractionComplete + (operation == .push ? 1.0 : -1.0) * direction * translation.x / width
            animator.fractionComplete = percent
            
            transitionContext.updateInteractiveTransition(percent)
            sender.setTranslation(.zero, in: transitionContext.containerView)
            
        case .ended, .cancelled:
            let position = completionPosition(for: animator, panGestureRecognizer: sender)
            position == .end ? transitionContext.finishInteractiveTransition() : transitionContext.cancelInteractiveTransition()
            
            animator.isReversed = position == .start
            animator.startAnimation()
            
        default:
            return
        }
    }
    
    @objc private func dismisslPan(_ sender: UIPanGestureRecognizer) {
        guard let animator = animator else { return }
        switch sender.state {
        case .began:
            animator.pauseAnimation()
            transitionContext.pauseInteractiveTransition()
        case .changed:
            let translation = sender.translation(in: transitionContext.containerView)
            let width = transitionContext.view(forKey: .from)?.bounds.width ?? transitionContext.containerView.bounds.width
            let direction: CGFloat = UIApplication.shared.userInterfaceLayoutDirection == .leftToRight ? 1.0 : -1.0
            let percent = animator.fractionComplete + (operation == .push ? 1.0 : -1.0) * direction * translation.x / width
            animator.fractionComplete = percent
            
            transitionContext.updateInteractiveTransition(percent)
            sender.setTranslation(.zero, in: transitionContext.containerView)
            
        case .ended, .cancelled:
            let position = completionPosition(for: animator, panGestureRecognizer: sender)
            position == .end ? transitionContext.finishInteractiveTransition() : transitionContext.cancelInteractiveTransition()
            
            animator.isReversed = position == .start
            animator.startAnimation()
            
        default:
            return
        }
    }
    
    private func completionPosition(for animator: UIViewPropertyAnimator, panGestureRecognizer: UIPanGestureRecognizer) -> UIViewAnimatingPosition {
        let completionThreshold: CGFloat = 0.33
        let flickMagnitude: CGFloat = 1200 // pts/sec
        let velocity = panGestureRecognizer.velocity(in: transitionContext.containerView).vector
        let direction: CGFloat = UIApplication.shared.userInterfaceLayoutDirection == .leftToRight ? 1.0 : -1.0
        let isFlick = (velocity.magnitude * direction > flickMagnitude)
        let isFlickRight = isFlick && (velocity.dx > 0.0)
        let isFlickLeft = isFlick && (velocity.dx < 0.0)
        
        if (operation == .push && isFlickRight) || (operation == .pop && isFlickLeft) {
            return .end
        } else if (operation == .push && isFlickLeft) || (operation == .pop && isFlickRight) {
            return .start
        } else if animator.fractionComplete > completionThreshold {
            return .end
        } else {
            return .start
        }
    }
    
}
