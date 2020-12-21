//
//  TouchBlockingView.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-12-17.
//  Copyright © 2020 Twidere. All rights reserved.
//

import UIKit

final class TouchBlockingView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        _init()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        _init()
    }
    
}

extension TouchBlockingView {
    
    private func _init() {
        isUserInteractionEnabled = true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Blocking responder chain by not call super
        // The subviews in this view will received touch event but superview not
    }
}
