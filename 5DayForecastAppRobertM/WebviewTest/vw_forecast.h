//
//  vw_forecast.h
//  WebviewTest
//
//  Created by Robert M on 4/17/18.
//  Copyright © 2018 Robert. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface vw_forecast : UIView
@property (strong, nonatomic) UILabel *lbl_date;
@property (strong, nonatomic) IBOutlet UILabel *lbl_high;
@property (strong, nonatomic) IBOutlet UILabel  *lbl_low;
@property (strong, nonatomic) IBOutlet UILabel  *lbl_desc;
@property (strong, nonatomic) IBOutlet UIImageView *img_desc;
@end
