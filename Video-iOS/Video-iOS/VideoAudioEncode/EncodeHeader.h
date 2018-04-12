//
//  EncodeHeader.h
//  Video-iOS
//
//  Created by zyyt on 2018/4/12.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#ifndef EncodeHeader_h
#define EncodeHeader_h

#ifdef DEBUG
//__VA_ARGS__代表可变参数宏
#define NSLog(...) NSLog(@"%s 第%d行 \n %@\n\n",__func__,__LINE__,[NSString stringWithFormat:__VA_ARGS__])//NSLog(format, ##__VA_ARGS__)
#else
#define NSLog(format, ...)
#endif

#endif /* EncodeHeader_h */
