// ============================================================================
// AnimationStudio for macOS — Полнофункциональная программа для анимаций
// Compile: clang++ -std=c++17 -framework Cocoa -framework QuartzCore
//          -framework CoreGraphics -framework AVFoundation -fobjc-arc
//          -O2 -o AnimationStudio main.mm
// ============================================================================

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVFoundation/AVFoundation.h>

#include <vector>
#include <string>
#include <memory>
#include <functional>
#include <algorithm>
#include <cmath>
#include <map>
#include <unordered_map>
#include <stack>
#include <random>
#include <sstream>
#include <fstream>
#include <optional>
#include <variant>
#include <chrono>
#include <numeric>

// ============================================================================
#pragma mark - Математика и утилиты
// ============================================================================

namespace Math {
    constexpr double PI = 3.14159265358979323846;
    constexpr double TAU = PI * 2.0;
    
    inline double lerp(double a, double b, double t) { return a + (b - a) * t; }
    inline double clamp(double v, double lo, double hi) { return std::max(lo, std::min(hi, v)); }
    inline double degToRad(double deg) { return deg * PI / 180.0; }
    inline double radToDeg(double rad) { return rad * 180.0 / PI; }
    inline double smoothstep(double edge0, double edge1, double x) {
        double t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }
    inline double map(double v, double inMin, double inMax, double outMin, double outMax) {
        return outMin + (outMax - outMin) * ((v - inMin) / (inMax - inMin));
    }
}

// ============================================================================
#pragma mark - Vec2 / Vec3
// ============================================================================

struct Vec2 {
    double x = 0, y = 0;
    Vec2() = default;
    Vec2(double x, double y) : x(x), y(y) {}
    Vec2 operator+(const Vec2& o) const { return {x+o.x, y+o.y}; }
    Vec2 operator-(const Vec2& o) const { return {x-o.x, y-o.y}; }
    Vec2 operator*(double s) const { return {x*s, y*s}; }
    Vec2 operator/(double s) const { return {x/s, y/s}; }
    Vec2& operator+=(const Vec2& o) { x+=o.x; y+=o.y; return *this; }
    Vec2& operator*=(double s) { x*=s; y*=s; return *this; }
    double length() const { return std::sqrt(x*x + y*y); }
    double lengthSq() const { return x*x + y*y; }
    Vec2 normalized() const { double l = length(); return l > 0 ? Vec2{x/l, y/l} : Vec2{0,0}; }
    double dot(const Vec2& o) const { return x*o.x + y*o.y; }
    double cross(const Vec2& o) const { return x*o.y - y*o.x; }
    double distanceTo(const Vec2& o) const { return (*this - o).length(); }
    Vec2 rotated(double angle) const {
        double c = std::cos(angle), s = std::sin(angle);
        return {x*c - y*s, x*s + y*c};
    }
    Vec2 lerp(const Vec2& o, double t) const { return {Math::lerp(x,o.x,t), Math::lerp(y,o.y,t)}; }
    NSPoint toNS() const { return NSMakePoint(x, y); }
    static Vec2 fromNS(NSPoint p) { return {p.x, p.y}; }
};

// ============================================================================
#pragma mark - Color
// ============================================================================

struct Color {
    double r = 1, g = 1, b = 1, a = 1;
    Color() = default;
    Color(double r, double g, double b, double a = 1.0) : r(r), g(g), b(b), a(a) {}
    
    Color lerp(const Color& o, double t) const {
        return {Math::lerp(r,o.r,t), Math::lerp(g,o.g,t),
                Math::lerp(b,o.b,t), Math::lerp(a,o.a,t)};
    }
    
    NSColor* toNS() const {
        return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
    }
    
    CGColorRef toCG() const {
        return CGColorCreateGenericRGB(r, g, b, a);
    }
    
    Color withAlpha(double newA) const { return {r, g, b, newA}; }
    
    static Color fromHSV(double h, double s, double v, double a = 1.0) {
        int i = (int)(h * 6);
        double f = h * 6 - i;
        double p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
        switch (i % 6) {
            case 0: return {v,t,p,a}; case 1: return {q,v,p,a};
            case 2: return {p,v,t,a}; case 3: return {p,q,v,a};
            case 4: return {t,p,v,a}; case 5: return {v,p,q,a};
        }
        return {v,v,v,a};
    }
    
    static Color red()     { return {1,0,0,1}; }
    static Color green()   { return {0,1,0,1}; }
    static Color blue()    { return {0,0,1,1}; }
    static Color white()   { return {1,1,1,1}; }
    static Color black()   { return {0,0,0,1}; }
    static Color yellow()  { return {1,1,0,1}; }
    static Color cyan()    { return {0,1,1,1}; }
    static Color magenta() { return {1,0,1,1}; }
    static Color orange()  { return {1,0.6,0,1}; }
    static Color gray(double v = 0.5) { return {v,v,v,1}; }
    static Color clear()   { return {0,0,0,0}; }
};

// ============================================================================
#pragma mark - Gradient
// ============================================================================

struct GradientStop {
    double position;
    Color color;
};

struct Gradient {
    std::vector<GradientStop> stops;
    bool isRadial = false;
    Vec2 startPoint = {0, 0};
    Vec2 endPoint = {1, 1};
    double radius = 100;
    
    Color sample(double t) const {
        if (stops.empty()) return Color::white();
        if (stops.size() == 1) return stops[0].color;
        t = Math::clamp(t, 0.0, 1.0);
        for (size_t i = 0; i < stops.size() - 1; ++i) {
            if (t >= stops[i].position && t <= stops[i+1].position) {
                double localT = (t - stops[i].position) / (stops[i+1].position - stops[i].position);
                return stops[i].color.lerp(stops[i+1].color, localT);
            }
        }
        return stops.back().color;
    }
    
    void addStop(double pos, Color col) {
        stops.push_back({pos, col});
        std::sort(stops.begin(), stops.end(), [](auto& a, auto& b) {
            return a.position < b.position;
        });
    }
};

// ============================================================================
#pragma mark - Transform2D
// ============================================================================

struct Transform2D {
    Vec2 position = {0, 0};
    Vec2 scale = {1, 1};
    double rotation = 0;
    Vec2 anchorPoint = {0.5, 0.5};
    Vec2 skew = {0, 0};
    
    Transform2D lerp(const Transform2D& o, double t) const {
        Transform2D r;
        r.position = position.lerp(o.position, t);
        r.scale = scale.lerp(o.scale, t);
        r.rotation = Math::lerp(rotation, o.rotation, t);
        r.anchorPoint = anchorPoint.lerp(o.anchorPoint, t);
        r.skew = skew.lerp(o.skew, t);
        return r;
    }
    
    CGAffineTransform toCG(double width, double height) const {
        double ax = anchorPoint.x * width;
        double ay = anchorPoint.y * height;
        CGAffineTransform t = CGAffineTransformIdentity;
        t = CGAffineTransformTranslate(t, position.x, position.y);
        t = CGAffineTransformTranslate(t, ax, ay);
        t = CGAffineTransformRotate(t, Math::degToRad(rotation));
        t = CGAffineTransformScale(t, scale.x, scale.y);
        if (skew.x != 0 || skew.y != 0) {
            CGAffineTransform sk = CGAffineTransformMake(1, std::tan(Math::degToRad(skew.y)),
                                                          std::tan(Math::degToRad(skew.x)), 1, 0, 0);
            t = CGAffineTransformConcat(sk, t);
        }
        t = CGAffineTransformTranslate(t, -ax, -ay);
        return t;
    }
};

// ============================================================================
#pragma mark - Easing Functions (30+ функций)
// ============================================================================

enum class EasingType {
    Linear, EaseInQuad, EaseOutQuad, EaseInOutQuad,
    EaseInCubic, EaseOutCubic, EaseInOutCubic,
    EaseInQuart, EaseOutQuart, EaseInOutQuart,
    EaseInQuint, EaseOutQuint, EaseInOutQuint,
    EaseInSine, EaseOutSine, EaseInOutSine,
    EaseInExpo, EaseOutExpo, EaseInOutExpo,
    EaseInCirc, EaseOutCirc, EaseInOutCirc,
    EaseInElastic, EaseOutElastic, EaseInOutElastic,
    EaseInBack, EaseOutBack, EaseInOutBack,
    EaseInBounce, EaseOutBounce, EaseInOutBounce,
    Spring, SmoothStep, SmootherStep,
    COUNT
};

namespace Easing {
    inline double linear(double t) { return t; }
    inline double easeInQuad(double t) { return t*t; }
    inline double easeOutQuad(double t) { return t*(2-t); }
    inline double easeInOutQuad(double t) { return t<0.5 ? 2*t*t : -1+(4-2*t)*t; }
    inline double easeInCubic(double t) { return t*t*t; }
    inline double easeOutCubic(double t) { double u=t-1; return u*u*u+1; }
    inline double easeInOutCubic(double t) { return t<0.5 ? 4*t*t*t : (t-1)*(2*t-2)*(2*t-2)+1; }
    inline double easeInQuart(double t) { return t*t*t*t; }
    inline double easeOutQuart(double t) { double u=t-1; return 1-u*u*u*u; }
    inline double easeInOutQuart(double t) { double u=t-1; return t<0.5 ? 8*t*t*t*t : 1-8*u*u*u*u; }
    inline double easeInQuint(double t) { return t*t*t*t*t; }
    inline double easeOutQuint(double t) { double u=t-1; return 1+u*u*u*u*u; }
    inline double easeInOutQuint(double t) { double u=t-1; return t<0.5 ? 16*t*t*t*t*t : 1+16*u*u*u*u*u; }
    inline double easeInSine(double t) { return 1-std::cos(t*Math::PI/2); }
    inline double easeOutSine(double t) { return std::sin(t*Math::PI/2); }
    inline double easeInOutSine(double t) { return 0.5*(1-std::cos(Math::PI*t)); }
    inline double easeInExpo(double t) { return t==0 ? 0 : std::pow(2,10*(t-1)); }
    inline double easeOutExpo(double t) { return t==1 ? 1 : 1-std::pow(2,-10*t); }
    inline double easeInOutExpo(double t) {
        if (t==0||t==1) return t;
        return t<0.5 ? std::pow(2,20*t-10)/2 : (2-std::pow(2,-20*t+10))/2;
    }
    inline double easeInCirc(double t) { return 1-std::sqrt(1-t*t); }
    inline double easeOutCirc(double t) { return std::sqrt(1-(t-1)*(t-1)); }
    inline double easeInOutCirc(double t) {
        return t<0.5 ? (1-std::sqrt(1-4*t*t))/2 : (std::sqrt(1-std::pow(-2*t+2,2))+1)/2;
    }
    inline double easeInElastic(double t) {
        if (t==0||t==1) return t;
        return -std::pow(2,10*t-10)*std::sin((t*10-10.75)*(2*Math::PI/3));
    }
    inline double easeOutElastic(double t) {
        if (t==0||t==1) return t;
        return std::pow(2,-10*t)*std::sin((t*10-0.75)*(2*Math::PI/3))+1;
    }
    inline double easeInOutElastic(double t) {
        if (t==0||t==1) return t;
        return t<0.5 ? -(std::pow(2,20*t-10)*std::sin((20*t-11.125)*(2*Math::PI/4.5)))/2
                      : (std::pow(2,-20*t+10)*std::sin((20*t-11.125)*(2*Math::PI/4.5)))/2+1;
    }
    inline double easeInBack(double t) { double c=1.70158; return (c+1)*t*t*t-c*t*t; }
    inline double easeOutBack(double t) { double c=1.70158; double u=t-1; return 1+(c+1)*u*u*u+c*u*u; }
    inline double easeInOutBack(double t) {
        double c=1.70158*1.525;
        return t<0.5 ? (std::pow(2*t,2)*((c+1)*2*t-c))/2
                      : (std::pow(2*t-2,2)*((c+1)*(t*2-2)+c)+2)/2;
    }
    inline double easeOutBounce(double t) {
        if (t<1/2.75) return 7.5625*t*t;
        if (t<2/2.75) { t-=1.5/2.75; return 7.5625*t*t+0.75; }
        if (t<2.5/2.75) { t-=2.25/2.75; return 7.5625*t*t+0.9375; }
        t-=2.625/2.75; return 7.5625*t*t+0.984375;
    }
    inline double easeInBounce(double t) { return 1-easeOutBounce(1-t); }
    inline double easeInOutBounce(double t) {
        return t<0.5 ? (1-easeOutBounce(1-2*t))/2 : (1+easeOutBounce(2*t-1))/2;
    }
    inline double spring(double t) {
        return 1 - std::cos(t * 4.5 * Math::PI) * std::exp(-t * 6);
    }
    inline double smoothStep(double t) { return t*t*(3-2*t); }
    inline double smootherStep(double t) { return t*t*t*(t*(t*6-15)+10); }
    
    inline double apply(EasingType type, double t) {
        switch (type) {
            case EasingType::Linear: return linear(t);
            case EasingType::EaseInQuad: return easeInQuad(t);
            case EasingType::EaseOutQuad: return easeOutQuad(t);
            case EasingType::EaseInOutQuad: return easeInOutQuad(t);
            case EasingType::EaseInCubic: return easeInCubic(t);
            case EasingType::EaseOutCubic: return easeOutCubic(t);
            case EasingType::EaseInOutCubic: return easeInOutCubic(t);
            case EasingType::EaseInQuart: return easeInQuart(t);
            case EasingType::EaseOutQuart: return easeOutQuart(t);
            case EasingType::EaseInOutQuart: return easeInOutQuart(t);
            case EasingType::EaseInQuint: return easeInQuint(t);
            case EasingType::EaseOutQuint: return easeOutQuint(t);
            case EasingType::EaseInOutQuint: return easeInOutQuint(t);
            case EasingType::EaseInSine: return easeInSine(t);
            case EasingType::EaseOutSine: return easeOutSine(t);
            case EasingType::EaseInOutSine: return easeInOutSine(t);
            case EasingType::EaseInExpo: return easeInExpo(t);
            case EasingType::EaseOutExpo: return easeOutExpo(t);
            case EasingType::EaseInOutExpo: return easeInOutExpo(t);
            case EasingType::EaseInCirc: return easeInCirc(t);
            case EasingType::EaseOutCirc: return easeOutCirc(t);
            case EasingType::EaseInOutCirc: return easeInOutCirc(t);
            case EasingType::EaseInElastic: return easeInElastic(t);
            case EasingType::EaseOutElastic: return easeOutElastic(t);
            case EasingType::EaseInOutElastic: return easeInOutElastic(t);
            case EasingType::EaseInBack: return easeInBack(t);
            case EasingType::EaseOutBack: return easeOutBack(t);
            case EasingType::EaseInOutBack: return easeInOutBack(t);
            case EasingType::EaseInBounce: return easeInBounce(t);
            case EasingType::EaseOutBounce: return easeOutBounce(t);
            case EasingType::EaseInOutBounce: return easeInOutBounce(t);
            case EasingType::Spring: return spring(t);
            case EasingType::SmoothStep: return smoothStep(t);
            case EasingType::SmootherStep: return smootherStep(t);
            default: return t;
        }
    }
    
    inline const char* name(EasingType type) {
        static const char* names[] = {
            "Linear","EaseInQuad","EaseOutQuad","EaseInOutQuad",
            "EaseInCubic","EaseOutCubic","EaseInOutCubic",
            "EaseInQuart","EaseOutQuart","EaseInOutQuart",
            "EaseInQuint","EaseOutQuint","EaseInOutQuint",
            "EaseInSine","EaseOutSine","EaseInOutSine",
            "EaseInExpo","EaseOutExpo","EaseInOutExpo",
            "EaseInCirc","EaseOutCirc","EaseInOutCirc",
            "EaseInElastic","EaseOutElastic","EaseInOutElastic",
            "EaseInBack","EaseOutBack","EaseInOutBack",
            "EaseInBounce","EaseOutBounce","EaseInOutBounce",
            "Spring","SmoothStep","SmootherStep"
        };
        return names[(int)type];
    }
}

// ============================================================================
#pragma mark - Bezier Curves
// ============================================================================

struct CubicBezier {
    Vec2 p0, p1, p2, p3;
    
    Vec2 evaluate(double t) const {
        double u = 1-t;
        return p0*(u*u*u) + p1*(3*u*u*t) + p2*(3*u*t*t) + p3*(t*t*t);
    }
    
    Vec2 tangent(double t) const {
        double u = 1-t;
        return (p1-p0)*(3*u*u) + (p2-p1)*(6*u*t) + (p3-p2)*(3*t*t);
    }
    
    double length(int steps = 100) const {
        double len = 0;
        Vec2 prev = p0;
        for (int i = 1; i <= steps; ++i) {
            Vec2 cur = evaluate((double)i / steps);
            len += prev.distanceTo(cur);
            prev = cur;
        }
        return len;
    }
    
    std::vector<Vec2> tessellate(int segments = 50) const {
        std::vector<Vec2> pts;
        for (int i = 0; i <= segments; ++i) {
            pts.push_back(evaluate((double)i / segments));
        }
        return pts;
    }
};

// ============================================================================
#pragma mark - Типы анимируемых свойств
// ============================================================================

enum class PropertyType {
    PositionX, PositionY, ScaleX, ScaleY, Rotation,
    Opacity, FillR, FillG, FillB, FillA,
    StrokeR, StrokeG, StrokeB, StrokeA, StrokeWidth,
    Width, Height, CornerRadius, SkewX, SkewY,
    AnchorX, AnchorY, BlurRadius, ShadowOffsetX, ShadowOffsetY,
    ShadowRadius, PathMorph,
    COUNT
};

inline const char* propertyName(PropertyType p) {
    static const char* names[] = {
        "Position X","Position Y","Scale X","Scale Y","Rotation",
        "Opacity","Fill R","Fill G","Fill B","Fill A",
        "Stroke R","Stroke G","Stroke B","Stroke A","Stroke Width",
        "Width","Height","Corner Radius","Skew X","Skew Y",
        "Anchor X","Anchor Y","Blur Radius","Shadow Offset X","Shadow Offset Y",
        "Shadow Radius","Path Morph"
    };
    return names[(int)p];
}

// ============================================================================
#pragma mark - Keyframe
// ============================================================================

struct Keyframe {
    int frame = 0;
    double value = 0;
    EasingType easing = EasingType::EaseInOutCubic;
    
    // Bezier handles для graph editor
    Vec2 handleIn = {-0.1, 0};
    Vec2 handleOut = {0.1, 0};
    bool hasBezierHandles = false;
};

// ============================================================================
#pragma mark - AnimationTrack
// ============================================================================

class AnimationTrack {
public:
    PropertyType property;
    std::vector<Keyframe> keyframes;
    bool enabled = true;
    
    AnimationTrack(PropertyType prop) : property(prop) {}
    
    void addKeyframe(int frame, double value, EasingType easing = EasingType::EaseInOutCubic) {
        // Удалить существующий кейфрейм на том же кадре
        keyframes.erase(std::remove_if(keyframes.begin(), keyframes.end(),
            [frame](const Keyframe& k) { return k.frame == frame; }), keyframes.end());
        keyframes.push_back({frame, value, easing});
        sortKeyframes();
    }
    
    void removeKeyframe(int frame) {
        keyframes.erase(std::remove_if(keyframes.begin(), keyframes.end(),
            [frame](const Keyframe& k) { return k.frame == frame; }), keyframes.end());
    }
    
    bool hasKeyframeAt(int frame) const {
        return std::any_of(keyframes.begin(), keyframes.end(),
            [frame](const Keyframe& k) { return k.frame == frame; });
    }
    
    double evaluate(int frame) const {
        if (keyframes.empty()) return 0;
        if (keyframes.size() == 1) return keyframes[0].value;
        if (frame <= keyframes.front().frame) return keyframes.front().value;
        if (frame >= keyframes.back().frame) return keyframes.back().value;
        
        for (size_t i = 0; i < keyframes.size() - 1; ++i) {
            if (frame >= keyframes[i].frame && frame <= keyframes[i+1].frame) {
                double t = (double)(frame - keyframes[i].frame) /
                           (double)(keyframes[i+1].frame - keyframes[i].frame);
                double easedT = Easing::apply(keyframes[i].easing, t);
                return Math::lerp(keyframes[i].value, keyframes[i+1].value, easedT);
            }
        }
        return keyframes.back().value;
    }
    
    double evaluateSmooth(double frameFloat) const {
        if (keyframes.empty()) return 0;
        if (keyframes.size() == 1) return keyframes[0].value;
        if (frameFloat <= keyframes.front().frame) return keyframes.front().value;
        if (frameFloat >= keyframes.back().frame) return keyframes.back().value;
        
        for (size_t i = 0; i < keyframes.size() - 1; ++i) {
            if (frameFloat >= keyframes[i].frame && frameFloat <= keyframes[i+1].frame) {
                double t = (frameFloat - keyframes[i].frame) /
                           (double)(keyframes[i+1].frame - keyframes[i].frame);
                double easedT = Easing::apply(keyframes[i].easing, t);
                return Math::lerp(keyframes[i].value, keyframes[i+1].value, easedT);
            }
        }
        return keyframes.back().value;
    }
    
    int firstFrame() const { return keyframes.empty() ? 0 : keyframes.front().frame; }
    int lastFrame() const { return keyframes.empty() ? 0 : keyframes.back().frame; }
    
private:
    void sortKeyframes() {
        std::sort(keyframes.begin(), keyframes.end(),
            [](const Keyframe& a, const Keyframe& b) { return a.frame < b.frame; });
    }
};

// ============================================================================
#pragma mark - Blend Mode
// ============================================================================

enum class BlendMode {
    Normal, Multiply, Screen, Overlay, Darken, Lighten,
    ColorDodge, ColorBurn, SoftLight, HardLight,
    Difference, Exclusion, Hue, Saturation, Color, Luminosity,
    COUNT
};

inline CGBlendMode toCGBlend(BlendMode m) {
    switch (m) {
        case BlendMode::Normal: return kCGBlendModeNormal;
        case BlendMode::Multiply: return kCGBlendModeMultiply;
        case BlendMode::Screen: return kCGBlendModeScreen;
        case BlendMode::Overlay: return kCGBlendModeOverlay;
        case BlendMode::Darken: return kCGBlendModeDarken;
        case BlendMode::Lighten: return kCGBlendModeLighten;
        case BlendMode::ColorDodge: return kCGBlendModeColorDodge;
        case BlendMode::ColorBurn: return kCGBlendModeColorBurn;
        case BlendMode::SoftLight: return kCGBlendModeSoftLight;
        case BlendMode::HardLight: return kCGBlendModeHardLight;
        case BlendMode::Difference: return kCGBlendModeDifference;
        case BlendMode::Exclusion: return kCGBlendModeExclusion;
        case BlendMode::Hue: return kCGBlendModeHue;
        case BlendMode::Saturation: return kCGBlendModeSaturation;
        case BlendMode::Color: return kCGBlendModeColor;
        case BlendMode::Luminosity: return kCGBlendModeLuminosity;
        default: return kCGBlendModeNormal;
    }
}

// ============================================================================
#pragma mark - Shape Types
// ============================================================================

enum class ShapeType {
    Rectangle, Ellipse, Triangle, Star, Polygon, Line,
    BezierPath, Text, Image, Group
};

// ============================================================================
#pragma mark - PathPoint (для Bezier Path)
// ============================================================================

struct PathPoint {
    Vec2 point;
    Vec2 controlIn;
    Vec2 controlOut;
    bool smooth = true;
};

// ============================================================================
#pragma mark - Shadow
// ============================================================================

struct Shadow {
    Color color = Color(0, 0, 0, 0.5);
    Vec2 offset = {3, -3};
    double radius = 5;
    bool enabled = false;
};

// ============================================================================
#pragma mark - AnimObject — Анимируемый объект
// ============================================================================

class AnimObject {
public:
    // Идентификация
    int id;
    std::string name;
    ShapeType shapeType = ShapeType::Rectangle;
    bool visible = true;
    bool locked = false;
    bool selected = false;
    
    // Визуальные свойства
    Color fillColor = Color::blue();
    Color strokeColor = Color::black();
    double strokeWidth = 2.0;
    double opacity = 1.0;
    double cornerRadius = 0;
    double width = 100, height = 100;
    BlendMode blendMode = BlendMode::Normal;
    Shadow shadow;
    double blurRadius = 0;
    
    // Трансформация
    Transform2D transform;
    
    // Для Star/Polygon
    int sides = 5;
    double innerRadius = 0.4;
    
    // Для Text
    std::string text = "Text";
    std::string fontName = "Helvetica";
    double fontSize = 24;
    
    // Для Bezier Path
    std::vector<PathPoint> pathPoints;
    bool closedPath = true;
    
    // Анимационные треки
    std::map<PropertyType, AnimationTrack> tracks;
    
    // Иерархия
    int parentId = -1;
    std::vector<int> childIds;
    
    // In/Out frames
    int inFrame = 0;
    int outFrame = 300;
    
    static int nextId;
    
    AnimObject() : id(nextId++) {
        name = "Object " + std::to_string(id);
    }
    
    AnimObject(ShapeType type, const std::string& n) : id(nextId++), name(n), shapeType(type) {}
    
    // Установить или создать трек
    AnimationTrack& getOrCreateTrack(PropertyType prop) {
        auto it = tracks.find(prop);
        if (it == tracks.end()) {
            tracks.emplace(prop, AnimationTrack(prop));
        }
        return tracks.at(prop);
    }
    
    bool hasAnimation() const { return !tracks.empty(); }
    
    void setKeyframe(PropertyType prop, int frame, double value,
                     EasingType easing = EasingType::EaseInOutCubic) {
        getOrCreateTrack(prop).addKeyframe(frame, value, easing);
    }
    
    double getPropertyValue(PropertyType prop) const {
        switch (prop) {
            case PropertyType::PositionX: return transform.position.x;
            case PropertyType::PositionY: return transform.position.y;
            case PropertyType::ScaleX: return transform.scale.x;
            case PropertyType::ScaleY: return transform.scale.y;
            case PropertyType::Rotation: return transform.rotation;
            case PropertyType::Opacity: return opacity;
            case PropertyType::FillR: return fillColor.r;
            case PropertyType::FillG: return fillColor.g;
            case PropertyType::FillB: return fillColor.b;
            case PropertyType::FillA: return fillColor.a;
            case PropertyType::StrokeR: return strokeColor.r;
            case PropertyType::StrokeG: return strokeColor.g;
            case PropertyType::StrokeB: return strokeColor.b;
            case PropertyType::StrokeA: return strokeColor.a;
            case PropertyType::StrokeWidth: return strokeWidth;
            case PropertyType::Width: return width;
            case PropertyType::Height: return height;
            case PropertyType::CornerRadius: return cornerRadius;
            case PropertyType::SkewX: return transform.skew.x;
            case PropertyType::SkewY: return transform.skew.y;
            case PropertyType::AnchorX: return transform.anchorPoint.x;
            case PropertyType::AnchorY: return transform.anchorPoint.y;
            case PropertyType::BlurRadius: return blurRadius;
            case PropertyType::ShadowOffsetX: return shadow.offset.x;
            case PropertyType::ShadowOffsetY: return shadow.offset.y;
            case PropertyType::ShadowRadius: return shadow.radius;
            default: return 0;
        }
    }
    
    void setPropertyValue(PropertyType prop, double val) {
        switch (prop) {
            case PropertyType::PositionX: transform.position.x = val; break;
            case PropertyType::PositionY: transform.position.y = val; break;
            case PropertyType::ScaleX: transform.scale.x = val; break;
            case PropertyType::ScaleY: transform.scale.y = val; break;
            case PropertyType::Rotation: transform.rotation = val; break;
            case PropertyType::Opacity: opacity = val; break;
            case PropertyType::FillR: fillColor.r = val; break;
            case PropertyType::FillG: fillColor.g = val; break;
            case PropertyType::FillB: fillColor.b = val; break;
            case PropertyType::FillA: fillColor.a = val; break;
            case PropertyType::StrokeR: strokeColor.r = val; break;
            case PropertyType::StrokeG: strokeColor.g = val; break;
            case PropertyType::StrokeB: strokeColor.b = val; break;
            case PropertyType::StrokeA: strokeColor.a = val; break;
            case PropertyType::StrokeWidth: strokeWidth = val; break;
            case PropertyType::Width: width = val; break;
            case PropertyType::Height: height = val; break;
            case PropertyType::CornerRadius: cornerRadius = val; break;
            case PropertyType::SkewX: transform.skew.x = val; break;
            case PropertyType::SkewY: transform.skew.y = val; break;
            case PropertyType::AnchorX: transform.anchorPoint.x = val; break;
            case PropertyType::AnchorY: transform.anchorPoint.y = val; break;
            case PropertyType::BlurRadius: blurRadius = val; break;
            case PropertyType::ShadowOffsetX: shadow.offset.x = val; break;
            case PropertyType::ShadowOffsetY: shadow.offset.y = val; break;
            case PropertyType::ShadowRadius: shadow.radius = val; break;
            default: break;
        }
    }
    
    void applyAnimationAtFrame(int frame) {
        if (frame < inFrame || frame > outFrame) { visible = false; return; }
        visible = true;
        for (auto& [prop, track] : tracks) {
            if (track.enabled && !track.keyframes.empty()) {
                setPropertyValue(prop, track.evaluate(frame));
            }
        }
    }
    
    NSBezierPath* createPath() const {
        NSBezierPath* path = [NSBezierPath bezierPath];
        switch (shapeType) {
            case ShapeType::Rectangle:
                if (cornerRadius > 0) {
                    [path appendBezierPathWithRoundedRect:NSMakeRect(0, 0, width, height)
                                                  xRadius:cornerRadius yRadius:cornerRadius];
                } else {
                    [path appendBezierPathWithRect:NSMakeRect(0, 0, width, height)];
                }
                break;
            case ShapeType::Ellipse:
                [path appendBezierPathWithOvalInRect:NSMakeRect(0, 0, width, height)];
                break;
            case ShapeType::Triangle: {
                [path moveToPoint:NSMakePoint(width/2, height)];
                [path lineToPoint:NSMakePoint(width, 0)];
                [path lineToPoint:NSMakePoint(0, 0)];
                [path closePath];
                break;
            }
            case ShapeType::Star: {
                double cx = width/2, cy = height/2;
                double outerR = std::min(width, height) / 2;
                double innerR2 = outerR * innerRadius;
                int pts = sides * 2;
                for (int i = 0; i < pts; ++i) {
                    double angle = Math::PI/2 + (2*Math::PI*i)/pts;
                    double r = (i % 2 == 0) ? outerR : innerR2;
                    double px = cx + r * std::cos(angle);
                    double py = cy + r * std::sin(angle);
                    if (i == 0) [path moveToPoint:NSMakePoint(px, py)];
                    else [path lineToPoint:NSMakePoint(px, py)];
                }
                [path closePath];
                break;
            }
            case ShapeType::Polygon: {
                double cx = width/2, cy = height/2;
                double r = std::min(width, height) / 2;
                for (int i = 0; i < sides; ++i) {
                    double angle = Math::PI/2 + (2*Math::PI*i)/sides;
                    double px = cx + r * std::cos(angle);
                    double py = cy + r * std::sin(angle);
                    if (i == 0) [path moveToPoint:NSMakePoint(px, py)];
                    else [path lineToPoint:NSMakePoint(px, py)];
                }
                [path closePath];
                break;
            }
            case ShapeType::Line: {
                [path moveToPoint:NSMakePoint(0, 0)];
                [path lineToPoint:NSMakePoint(width, height)];
                break;
            }
            case ShapeType::BezierPath: {
                if (pathPoints.size() >= 2) {
                    [path moveToPoint:pathPoints[0].point.toNS()];
                    for (size_t i = 1; i < pathPoints.size(); ++i) {
                        [path curveToPoint:pathPoints[i].point.toNS()
                             controlPoint1:pathPoints[i-1].controlOut.toNS()
                             controlPoint2:pathPoints[i].controlIn.toNS()];
                    }
                    if (closedPath) [path closePath];
                }
                break;
            }
            default: break;
        }
        return path;
    }
    
    bool hitTest(Vec2 point) const {
        Vec2 local = point - transform.position;
        if (transform.rotation != 0) {
            local = local.rotated(-Math::degToRad(transform.rotation));
        }
        local.x /= transform.scale.x;
        local.y /= transform.scale.y;
        return local.x >= 0 && local.x <= width && local.y >= 0 && local.y <= height;
    }
    
    NSRect getBounds() const {
        return NSMakeRect(transform.position.x, transform.position.y, width, height);
    }
};

int AnimObject::nextId = 1;

// ============================================================================
#pragma mark - Particle System
// ============================================================================

struct Particle {
    Vec2 position;
    Vec2 velocity;
    Vec2 acceleration;
    Color color;
    Color endColor;
    double life = 1.0;
    double maxLife = 1.0;
    double size = 5;
    double endSize = 0;
    double rotation = 0;
    double rotationSpeed = 0;
    double alpha = 1;
    bool alive = true;
};

class ParticleEmitter {
public:
    Vec2 position = {400, 300};
    double emissionRate = 50; // частиц в секунду
    double emissionAngle = 0;
    double emissionSpread = Math::TAU; // полный круг
    double speed = 100;
    double speedVariance = 30;
    double life = 2.0;
    double lifeVariance = 0.5;
    double startSize = 10;
    double endSize = 0;
    double sizeVariance = 3;
    Color startColor = Color::orange();
    Color endColor = Color::red().withAlpha(0);
    Vec2 gravity = {0, -100};
    double rotationSpeed = 0;
    double rotationVariance = 30;
    int maxParticles = 500;
    bool active = true;
    bool burst = false;
    int burstCount = 100;
    
    std::vector<Particle> particles;
    
private:
    std::mt19937 rng{std::random_device{}()};
    double emissionAccum = 0;
    
    double randRange(double lo, double hi) {
        std::uniform_real_distribution<double> dist(lo, hi);
        return dist(rng);
    }
    
public:
    void emit(int count = 1) {
        for (int i = 0; i < count && (int)particles.size() < maxParticles; ++i) {
            Particle p;
            p.position = position;
            double angle = emissionAngle + randRange(-emissionSpread/2, emissionSpread/2);
            double spd = speed + randRange(-speedVariance, speedVariance);
            p.velocity = {spd * std::cos(angle), spd * std::sin(angle)};
            p.acceleration = gravity;
            p.life = life + randRange(-lifeVariance, lifeVariance);
            p.maxLife = p.life;
            p.size = startSize + randRange(-sizeVariance, sizeVariance);
            p.endSize = endSize;
            p.color = startColor;
            p.endColor = endColor;
            p.rotation = randRange(0, Math::TAU);
            p.rotationSpeed = rotationSpeed + randRange(-rotationVariance, rotationVariance);
            particles.push_back(p);
        }
    }
    
    void update(double dt) {
        if (active && !burst) {
            emissionAccum += emissionRate * dt;
            while (emissionAccum >= 1.0) {
                emit(1);
                emissionAccum -= 1.0;
            }
        }
        
        for (auto& p : particles) {
            if (!p.alive) continue;
            p.life -= dt;
            if (p.life <= 0) { p.alive = false; continue; }
            p.velocity += p.acceleration * dt;
            p.position += p.velocity * dt;
            p.rotation += p.rotationSpeed * dt;
            double t = 1.0 - (p.life / p.maxLife);
            p.alpha = Math::lerp(1.0, 0.0, t);
            p.size = Math::lerp(startSize, endSize, t);
        }
        
        particles.erase(std::remove_if(particles.begin(), particles.end(),
            [](const Particle& p) { return !p.alive; }), particles.end());
    }
    
    void draw(CGContextRef ctx) {
        for (auto& p : particles) {
            if (!p.alive) continue;
            double t = 1.0 - (p.life / p.maxLife);
            Color c = p.color.lerp(p.endColor, t);
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, p.position.x, p.position.y);
            CGContextRotateCTM(ctx, p.rotation);
            CGContextSetFillColorWithColor(ctx, c.toCG());
            CGContextFillEllipseInRect(ctx,
                CGRectMake(-p.size/2, -p.size/2, p.size, p.size));
            CGContextRestoreGState(ctx);
        }
    }
    
    void doBurst() {
        emit(burstCount);
    }
};

// ============================================================================
#pragma mark - Undo/Redo System
// ============================================================================

class UndoAction {
public:
    std::string description;
    std::function<void()> undoFn;
    std::function<void()> redoFn;
};

class UndoManager {
    std::stack<UndoAction> undoStack;
    std::stack<UndoAction> redoStack;
    int maxSize = 100;
public:
    void addAction(const std::string& desc, std::function<void()> undo, std::function<void()> redo) {
        undoStack.push({desc, undo, redo});
        while (!redoStack.empty()) redoStack.pop();
        if ((int)undoStack.size() > maxSize) {
            // Ограничиваем размер — для простоты не делаем, стек и так ОК
        }
    }
    bool canUndo() const { return !undoStack.empty(); }
    bool canRedo() const { return !redoStack.empty(); }
    void undo() {
        if (!canUndo()) return;
        auto action = undoStack.top(); undoStack.pop();
        action.undoFn();
        redoStack.push(action);
    }
    void redo() {
        if (!canRedo()) return;
        auto action = redoStack.top(); redoStack.pop();
        action.redoFn();
        undoStack.push(action);
    }
    std::string undoDescription() const {
        return canUndo() ? undoStack.top().description : "";
    }
    std::string redoDescription() const {
        return canRedo() ? redoStack.top().description : "";
    }
};

// ============================================================================
#pragma mark - Project
// ============================================================================

class Project {
public:
    std::string name = "Untitled";
    int canvasWidth = 1280;
    int canvasHeight = 720;
    int fps = 30;
    int totalFrames = 300;
    Color backgroundColor = Color(0.15, 0.15, 0.15);
    bool showGrid = true;
    int gridSize = 20;
    bool snapToGrid = false;
    bool onionSkinning = false;
    int onionSkinFrames = 3;
    double onionSkinOpacity = 0.2;
    
    std::vector<std::shared_ptr<AnimObject>> objects;
    std::vector<std::shared_ptr<ParticleEmitter>> emitters;
    UndoManager undoManager;
    
    int currentFrame = 0;
    int selectedObjectId = -1;
    bool playing = false;
    double playbackSpeed = 1.0;
    bool looping = true;
    
    // Камера/Viewport
    Vec2 viewOffset = {0, 0};
    double viewZoom = 1.0;
    
    std::shared_ptr<AnimObject> addObject(ShapeType type, const std::string& name) {
        auto obj = std::make_shared<AnimObject>(type, name);
        obj->transform.position = {(double)canvasWidth/2 - 50, (double)canvasHeight/2 - 50};
        objects.push_back(obj);
        return obj;
    }
    
    void removeObject(int objId) {
        objects.erase(std::remove_if(objects.begin(), objects.end(),
            [objId](auto& o) { return o->id == objId; }), objects.end());
        if (selectedObjectId == objId) selectedObjectId = -1;
    }
    
    std::shared_ptr<AnimObject> findObject(int id) {
        for (auto& o : objects) if (o->id == id) return o;
        return nullptr;
    }
    
    std::shared_ptr<AnimObject> selectedObject() {
        return findObject(selectedObjectId);
    }
    
    void updateFrame(int frame) {
        currentFrame = frame;
        for (auto& obj : objects) {
            obj->applyAnimationAtFrame(frame);
        }
        for (auto& emitter : emitters) {
            emitter->update(1.0 / fps);
        }
    }
    
    void moveObjectUp(int objId) {
        for (size_t i = 1; i < objects.size(); ++i) {
            if (objects[i]->id == objId) {
                std::swap(objects[i], objects[i-1]);
                break;
            }
        }
    }
    
    void moveObjectDown(int objId) {
        for (size_t i = 0; i + 1 < objects.size(); ++i) {
            if (objects[i]->id == objId) {
                std::swap(objects[i], objects[i+1]);
                break;
            }
        }
    }
    
    std::shared_ptr<AnimObject> hitTest(Vec2 point) {
        for (auto it = objects.rbegin(); it != objects.rend(); ++it) {
            if ((*it)->visible && !(*it)->locked && (*it)->hitTest(point)) {
                return *it;
            }
        }
        return nullptr;
    }
    
    Vec2 screenToCanvas(NSPoint screenPt) {
        return {(screenPt.x - viewOffset.x) / viewZoom,
                (screenPt.y - viewOffset.y) / viewZoom};
    }
    
    NSPoint canvasToScreen(Vec2 canvasPt) {
        return NSMakePoint(canvasPt.x * viewZoom + viewOffset.x,
                          canvasPt.y * viewZoom + viewOffset.y);
    }
    
    void duplicateObject(int objId) {
        auto src = findObject(objId);
        if (!src) return;
        auto copy = std::make_shared<AnimObject>(*src);
        copy->id = AnimObject::nextId++;
        copy->name = src->name + " Copy";
        copy->transform.position.x += 20;
        copy->transform.position.y -= 20;
        objects.push_back(copy);
    }
};

static Project gProject;

// ============================================================================
#pragma mark - Canvas View
// ============================================================================

@interface CanvasView : NSView {
    NSPoint dragStart;
    NSPoint dragObjStart;
    BOOL dragging;
    BOOL panning;
    int resizeHandle; // 0=none, 1-8=corner/edge handles
    NSTrackingArea* trackArea;
}
@end

@implementation CanvasView

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)updateTrackingAreas {
    if (trackArea) [self removeTrackingArea:trackArea];
    trackArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
        options:NSTrackingMouseMoved|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:trackArea];
    [super updateTrackingAreas];
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    
    // Фон окна
    CGContextSetFillColorWithColor(ctx, Color(0.2, 0.2, 0.22).toCG());
    CGContextFillRect(ctx, NSRectToCGRect(self.bounds));
    
    CGContextSaveGState(ctx);
    
    // Применяем viewport transform
    CGContextTranslateCTM(ctx, gProject.viewOffset.x, gProject.viewOffset.y);
    CGContextScaleCTM(ctx, gProject.viewZoom, gProject.viewZoom);
    
    // Рисуем canvas (рабочую область)
    CGRect canvasRect = CGRectMake(0, 0, gProject.canvasWidth, gProject.canvasHeight);
    
    // Тень канваса
    CGContextSetShadow(ctx, CGSizeMake(5, 5), 10);
    CGContextSetFillColorWithColor(ctx, gProject.backgroundColor.toCG());
    CGContextFillRect(ctx, canvasRect);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    
    // Сетка
    if (gProject.showGrid) {
        CGContextSetStrokeColorWithColor(ctx, Color(1, 1, 1, 0.06).toCG());
        CGContextSetLineWidth(ctx, 0.5);
        for (int x = 0; x <= gProject.canvasWidth; x += gProject.gridSize) {
            CGContextMoveToPoint(ctx, x, 0);
            CGContextAddLineToPoint(ctx, x, gProject.canvasHeight);
        }
        for (int y = 0; y <= gProject.canvasHeight; y += gProject.gridSize) {
            CGContextMoveToPoint(ctx, 0, y);
            CGContextAddLineToPoint(ctx, gProject.canvasWidth, y);
        }
        CGContextStrokePath(ctx);
    }
    
    // Clip to canvas
    CGContextClipToRect(ctx, canvasRect);
    
    // Onion skinning
    if (gProject.onionSkinning && !gProject.playing) {
        for (int offset = -gProject.onionSkinFrames; offset <= gProject.onionSkinFrames; ++offset) {
            if (offset == 0) continue;
            int frame = gProject.currentFrame + offset;
            if (frame < 0 || frame >= gProject.totalFrames) continue;
            
            CGContextSaveGState(ctx);
            double alpha = gProject.onionSkinOpacity * (1.0 - std::abs(offset) / (double)(gProject.onionSkinFrames + 1));
            CGContextSetAlpha(ctx, alpha);
            
            for (auto& obj : gProject.objects) {
                auto saved = *obj;
                obj->applyAnimationAtFrame(frame);
                if (obj->visible) {
                    [self drawObject:obj.get() inContext:ctx tintColor:(offset < 0 ? Color(0,0.5,1,0.3) : Color(1,0.3,0,0.3))];
                }
                *obj = saved;
            }
            CGContextRestoreGState(ctx);
        }
    }
    
    // Рисуем объекты
    for (auto& obj : gProject.objects) {
        if (!obj->visible) continue;
        [self drawObject:obj.get() inContext:ctx tintColor:Color::clear()];
    }
    
    // Рисуем частицы
    for (auto& emitter : gProject.emitters) {
        emitter->draw(ctx);
    }
    
    // Рисуем рамку выделения
    if (auto sel = gProject.selectedObject()) {
        CGContextSetStrokeColorWithColor(ctx, Color(0.2, 0.6, 1.0, 1.0).toCG());
        CGContextSetLineWidth(ctx, 1.5 / gProject.viewZoom);
        CGFloat dashes[] = {6.0 / gProject.viewZoom, 3.0 / gProject.viewZoom};
        CGContextSetLineDash(ctx, 0, dashes, 2);
        
        CGContextSaveGState(ctx);
        CGAffineTransform t = sel->transform.toCG(sel->width, sel->height);
        CGContextConcatCTM(ctx, t);
        CGContextStrokeRect(ctx, CGRectMake(-2, -2, sel->width+4, sel->height+4));
        
        // Handles
        CGContextSetLineDash(ctx, 0, NULL, 0);
        double hs = 6 / gProject.viewZoom;
        CGContextSetFillColorWithColor(ctx, Color::white().toCG());
        CGRect handles[] = {
            CGRectMake(-hs, -hs, hs*2, hs*2),
            CGRectMake(sel->width/2-hs, -hs, hs*2, hs*2),
            CGRectMake(sel->width-hs, -hs, hs*2, hs*2),
            CGRectMake(sel->width-hs, sel->height/2-hs, hs*2, hs*2),
            CGRectMake(sel->width-hs, sel->height-hs, hs*2, hs*2),
            CGRectMake(sel->width/2-hs, sel->height-hs, hs*2, hs*2),
            CGRectMake(-hs, sel->height-hs, hs*2, hs*2),
            CGRectMake(-hs, sel->height/2-hs, hs*2, hs*2),
        };
        for (int i = 0; i < 8; ++i) {
            CGContextFillRect(ctx, handles[i]);
            CGContextStrokeRect(ctx, handles[i]);
        }
        CGContextRestoreGState(ctx);
    }
    
    CGContextRestoreGState(ctx);
    
    // HUD информация
    [self drawHUD:ctx];
}

- (void)drawObject:(AnimObject*)obj inContext:(CGContextRef)ctx tintColor:(Color)tint {
    CGContextSaveGState(ctx);
    
    CGContextSetAlpha(ctx, obj->opacity);
    CGContextSetBlendMode(ctx, toCGBlend(obj->blendMode));
    
    CGAffineTransform t = obj->transform.toCG(obj->width, obj->height);
    CGContextConcatCTM(ctx, t);
    
    // Тень
    if (obj->shadow.enabled) {
        CGContextSetShadowWithColor(ctx,
            CGSizeMake(obj->shadow.offset.x, obj->shadow.offset.y),
            obj->shadow.radius, obj->shadow.color.toCG());
    }
    
    // Размытие
    if (obj->blurRadius > 0) {
        // CG не поддерживает blur напрямую, имитируем через shadow trick
    }
    
    if (obj->shapeType == ShapeType::Text) {
        NSString* str = [NSString stringWithUTF8String:obj->text.c_str()];
        NSFont* font = [NSFont fontWithName:[NSString stringWithUTF8String:obj->fontName.c_str()]
                                       size:obj->fontSize];
        if (!font) font = [NSFont systemFontOfSize:obj->fontSize];
        
        NSDictionary* attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: obj->fillColor.toNS()
        };
        [str drawAtPoint:NSZeroPoint withAttributes:attrs];
    } else {
        NSBezierPath* path = obj->createPath();
        
        // Fill
        if (tint.a > 0) {
            [tint.toNS() setFill];
        } else {
            [obj->fillColor.toNS() setFill];
        }
        [path fill];
        
        // Stroke
        if (obj->strokeWidth > 0) {
            [obj->strokeColor.toNS() setStroke];
            [path setLineWidth:obj->strokeWidth];
            [path stroke];
        }
    }
    
    CGContextRestoreGState(ctx);
}

- (void)drawHUD:(CGContextRef)ctx {
    // Frame counter
    NSString* info = [NSString stringWithFormat:@"Frame: %d/%d  |  FPS: %d  |  Zoom: %.0f%%  |  Objects: %lu",
                      gProject.currentFrame, gProject.totalFrames,
                      gProject.fps, gProject.viewZoom * 100,
                      (unsigned long)gProject.objects.size()];
    NSDictionary* attrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.8 alpha:0.9]
    };
    [info drawAtPoint:NSMakePoint(10, 5) withAttributes:attrs];
    
    if (gProject.playing) {
        NSDictionary* playAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0]
        };
        [@"▶ PLAYING" drawAtPoint:NSMakePoint(self.bounds.size.width - 120, 5) withAttributes:playAttrs];
    }
}

- (void)mouseDown:(NSEvent*)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    Vec2 canvasPos = gProject.screenToCanvas(loc);
    
    if (event.modifierFlags & NSEventModifierFlagOption) {
        panning = YES;
        dragStart = loc;
        return;
    }
    
    auto hit = gProject.hitTest(canvasPos);
    if (hit) {
        gProject.selectedObjectId = hit->id;
        dragging = YES;
        dragStart = loc;
        dragObjStart = NSMakePoint(hit->transform.position.x, hit->transform.position.y);
    } else {
        gProject.selectedObjectId = -1;
    }
    [self setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectionChanged" object:nil];
}

- (void)mouseDragged:(NSEvent*)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    
    if (panning) {
        gProject.viewOffset.x += loc.x - dragStart.x;
        gProject.viewOffset.y += loc.y - dragStart.y;
        dragStart = loc;
        [self setNeedsDisplay:YES];
        return;
    }
    
    if (dragging) {
        if (auto sel = gProject.selectedObject()) {
            double dx = (loc.x - dragStart.x) / gProject.viewZoom;
            double dy = (loc.y - dragStart.y) / gProject.viewZoom;
            sel->transform.position.x = dragObjStart.x + dx;
            sel->transform.position.y = dragObjStart.y + dy;
            
            if (gProject.snapToGrid) {
                int gs = gProject.gridSize;
                sel->transform.position.x = std::round(sel->transform.position.x / gs) * gs;
                sel->transform.position.y = std::round(sel->transform.position.y / gs) * gs;
            }
            
            [self setNeedsDisplay:YES];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PropertyChanged" object:nil];
        }
    }
}

- (void)mouseUp:(NSEvent*)event {
    dragging = NO;
    panning = NO;
}

- (void)scrollWheel:(NSEvent*)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        // Zoom
        double zoomDelta = event.deltaY * 0.05;
        NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
        double oldZoom = gProject.viewZoom;
        gProject.viewZoom = Math::clamp(gProject.viewZoom + zoomDelta, 0.1, 10.0);
        
        // Zoom towards cursor
        double zoomRatio = gProject.viewZoom / oldZoom;
        gProject.viewOffset.x = loc.x - (loc.x - gProject.viewOffset.x) * zoomRatio;
        gProject.viewOffset.y = loc.y - (loc.y - gProject.viewOffset.y) * zoomRatio;
    } else {
        gProject.viewOffset.x += event.deltaX * 2;
        gProject.viewOffset.y += event.deltaY * 2;
    }
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent*)event {
    unichar key = [[event characters] characterAtIndex:0];
    
    switch (key) {
        case ' ':
            gProject.playing = !gProject.playing;
            break;
        case 127: // Delete
        case NSDeleteCharacter:
            if (gProject.selectedObjectId >= 0) {
                gProject.removeObject(gProject.selectedObjectId);
            }
            break;
        case '0':
            gProject.viewZoom = 1.0;
            gProject.viewOffset = {50, 50};
            break;
        case '+': case '=':
            gProject.viewZoom = Math::clamp(gProject.viewZoom * 1.2, 0.1, 10.0);
            break;
        case '-':
            gProject.viewZoom = Math::clamp(gProject.viewZoom / 1.2, 0.1, 10.0);
            break;
        case 'g':
            gProject.showGrid = !gProject.showGrid;
            break;
        case 's':
            gProject.snapToGrid = !gProject.snapToGrid;
            break;
        case 'o':
            gProject.onionSkinning = !gProject.onionSkinning;
            break;
        case 'd':
            if (gProject.selectedObjectId >= 0) {
                gProject.duplicateObject(gProject.selectedObjectId);
            }
            break;
        case NSLeftArrowFunctionKey:
            if (gProject.currentFrame > 0) gProject.updateFrame(gProject.currentFrame - 1);
            break;
        case NSRightArrowFunctionKey:
            if (gProject.currentFrame < gProject.totalFrames - 1) gProject.updateFrame(gProject.currentFrame + 1);
            break;
    }
    [self setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FrameChanged" object:nil];
}

@end

// ============================================================================
#pragma mark - Timeline View
// ============================================================================

@interface TimelineView : NSView {
    BOOL scrubbing;
}
@end

@implementation TimelineView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect bounds = self.bounds;
    
    // Фон
    CGContextSetFillColorWithColor(ctx, Color(0.16, 0.16, 0.18).toCG());
    CGContextFillRect(ctx, NSRectToCGRect(bounds));
    
    double trackHeight = 28;
    double headerWidth = 160;
    double framesWidth = bounds.size.width - headerWidth;
    double frameWidth = framesWidth / (double)gProject.totalFrames;
    if (frameWidth < 2) frameWidth = 2;
    
    // Линейка кадров
    CGContextSetFillColorWithColor(ctx, Color(0.22, 0.22, 0.25).toCG());
    CGContextFillRect(ctx, CGRectMake(headerWidth, 0, framesWidth, 24));
    
    // Номера кадров
    NSDictionary* numAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.6 alpha:1.0]
    };
    int step = std::max(1, (int)(30.0 / frameWidth));
    for (int f = 0; f < gProject.totalFrames; f += step) {
        double x = headerWidth + f * frameWidth;
        [[NSString stringWithFormat:@"%d", f] drawAtPoint:NSMakePoint(x + 2, 4) withAttributes:numAttrs];
        CGContextSetStrokeColorWithColor(ctx, Color(0.35, 0.35, 0.38).toCG());
        CGContextSetLineWidth(ctx, 0.5);
        CGContextMoveToPoint(ctx, x, 20);
        CGContextAddLineToPoint(ctx, x, bounds.size.height);
        CGContextStrokePath(ctx);
    }
    
    // Треки для каждого объекта
    double y = 26;
    for (auto& obj : gProject.objects) {
        bool isSel = (obj->id == gProject.selectedObjectId);
        
        // Заголовок трека
        Color bgColor = isSel ? Color(0.25, 0.35, 0.5) : Color(0.19, 0.19, 0.22);
        CGContextSetFillColorWithColor(ctx, bgColor.toCG());
        CGContextFillRect(ctx, CGRectMake(0, y, headerWidth, trackHeight));
        
        // Имя объекта
        NSDictionary* nameAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11 weight:(isSel ? NSFontWeightBold : NSFontWeightRegular)],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.85 alpha:1.0]
        };
        NSString* icon = @"■";
        switch (obj->shapeType) {
            case ShapeType::Ellipse: icon = @"●"; break;
            case ShapeType::Triangle: icon = @"▲"; break;
            case ShapeType::Star: icon = @"★"; break;
            case ShapeType::Text: icon = @"T"; break;
            case ShapeType::Line: icon = @"╲"; break;
            case ShapeType::BezierPath: icon = @"◇"; break;
            default: break;
        }
        NSString* label = [NSString stringWithFormat:@"%@ %s%s",
                          icon, obj->name.c_str(),
                          obj->locked ? " 🔒" : ""];
        [label drawAtPoint:NSMakePoint(8, y + 6) withAttributes:nameAttrs];
        
        // Область анимации объекта
        Color trackBg = isSel ? Color(0.2, 0.28, 0.4, 0.5) : Color(0.15, 0.15, 0.17, 0.5);
        CGContextSetFillColorWithColor(ctx, trackBg.toCG());
        double inX = headerWidth + obj->inFrame * frameWidth;
        double outX = headerWidth + obj->outFrame * frameWidth;
        CGContextFillRect(ctx, CGRectMake(inX, y + 2, outX - inX, trackHeight - 4));
        
        // Рисуем keyframes
        for (auto& [prop, track] : obj->tracks) {
            for (auto& kf : track.keyframes) {
                double kfX = headerWidth + kf.frame * frameWidth;
                CGContextSetFillColorWithColor(ctx, Color(1.0, 0.8, 0.2, 1.0).toCG());
                double ds = 4;
                // Ромбик
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, kfX, y + trackHeight/2);
                CGContextRotateCTM(ctx, Math::PI/4);
                CGContextFillRect(ctx, CGRectMake(-ds, -ds, ds*2, ds*2));
                CGContextRestoreGState(ctx);
            }
        }
        
        // Разделительная линия
        CGContextSetStrokeColorWithColor(ctx, Color(0.3, 0.3, 0.32).toCG());
        CGContextSetLineWidth(ctx, 0.5);
        CGContextMoveToPoint(ctx, 0, y + trackHeight);
        CGContextAddLineToPoint(ctx, bounds.size.width, y + trackHeight);
        CGContextStrokePath(ctx);
        
        y += trackHeight;
    }
    
    // Playhead (индикатор текущего кадра)
    double phX = headerWidth + gProject.currentFrame * frameWidth;
    CGContextSetStrokeColorWithColor(ctx, Color(1.0, 0.3, 0.3, 1.0).toCG());
    CGContextSetLineWidth(ctx, 2);
    CGContextMoveToPoint(ctx, phX, 0);
    CGContextAddLineToPoint(ctx, phX, bounds.size.height);
    CGContextStrokePath(ctx);
    
    // Треугольник playhead
    CGContextSetFillColorWithColor(ctx, Color(1.0, 0.3, 0.3, 1.0).toCG());
    CGContextMoveToPoint(ctx, phX - 6, 0);
    CGContextAddLineToPoint(ctx, phX + 6, 0);
    CGContextAddLineToPoint(ctx, phX, 10);
    CGContextFillPath(ctx);
}

- (void)mouseDown:(NSEvent*)event {
    scrubbing = YES;
    [self handleScrub:event];
}

- (void)mouseDragged:(NSEvent*)event {
    if (scrubbing) [self handleScrub:event];
}

- (void)mouseUp:(NSEvent*)event {
    scrubbing = NO;
}

- (void)handleScrub:(NSEvent*)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    double headerWidth = 160;
    double framesWidth = self.bounds.size.width - headerWidth;
    double frameWidth = framesWidth / (double)gProject.totalFrames;
    
    // Проверяем клик по имени объекта
    if (loc.x < headerWidth) {
        double y = 26;
        for (auto& obj : gProject.objects) {
            if (loc.y >= y && loc.y < y + 28) {
                gProject.selectedObjectId = obj->id;
                [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectionChanged" object:nil];
                break;
            }
            y += 28;
        }
    } else {
        int frame = (int)((loc.x - headerWidth) / frameWidth);
        frame = Math::clamp(frame, 0, gProject.totalFrames - 1);
        gProject.updateFrame(frame);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"FrameChanged" object:nil];
    }
    [self setNeedsDisplay:YES];
    // Перерисовать canvas
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Redraw" object:nil];
}

@end

// ============================================================================
#pragma mark - Property Inspector View
// ============================================================================

@interface InspectorView : NSView
@property (nonatomic, strong) NSScrollView* scrollView;
@end

@implementation InspectorView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSetFillColorWithColor(ctx, Color(0.17, 0.17, 0.19).toCG());
    CGContextFillRect(ctx, NSRectToCGRect(self.bounds));
    
    auto sel = gProject.selectedObject();
    double y = 10;
    double padding = 10;
    double labelWidth = 90;
    double valueX = labelWidth + padding;
    
    NSDictionary* headerAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.9 alpha:1.0]
    };
    NSDictionary* labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.7 alpha:1.0]
    };
    NSDictionary* valueAttrs = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.95 alpha:1.0]
    };
    
    if (!sel) {
        [@"No Selection" drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
        y += 30;
        
        NSDictionary* hintAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.5 alpha:1.0]
        };
        [@"Select an object on canvas\nor add one from the menu." drawAtPoint:NSMakePoint(padding, y)
                                                                withAttributes:hintAttrs];
        return;
    }
    
    // Заголовок
    NSString* title = [NSString stringWithFormat:@"📐 %s", sel->name.c_str()];
    [title drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
    y += 24;
    
    // Разделитель
    CGContextSetStrokeColorWithColor(ctx, Color(0.3, 0.3, 0.33).toCG());
    CGContextSetLineWidth(ctx, 0.5);
    CGContextMoveToPoint(ctx, padding, y);
    CGContextAddLineToPoint(ctx, self.bounds.size.width - padding, y);
    CGContextStrokePath(ctx);
    y += 8;
    
    // Transform
    [@"⊞ Transform" drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
    y += 20;
    
    auto drawProp = [&](const char* label, double value) {
        [[NSString stringWithUTF8String:label] drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
        [[NSString stringWithFormat:@"%.1f", value] drawAtPoint:NSMakePoint(valueX, y) withAttributes:valueAttrs];
        y += 18;
    };
    
    drawProp("Position X", sel->transform.position.x);
    drawProp("Position Y", sel->transform.position.y);
    drawProp("Scale X", sel->transform.scale.x);
    drawProp("Scale Y", sel->transform.scale.y);
    drawProp("Rotation", sel->transform.rotation);
    drawProp("Skew X", sel->transform.skew.x);
    drawProp("Skew Y", sel->transform.skew.y);
    y += 6;
    
    // Size
    [@"📏 Size" drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
    y += 20;
    drawProp("Width", sel->width);
    drawProp("Height", sel->height);
    if (sel->shapeType == ShapeType::Rectangle) {
        drawProp("Corner R", sel->cornerRadius);
    }
    y += 6;
    
    // Appearance
    [@"🎨 Appearance" drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
    y += 20;
    drawProp("Opacity", sel->opacity);
    drawProp("Stroke W", sel->strokeWidth);
    
    // Color swatches
    [@"Fill:" drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
    CGContextSetFillColorWithColor(ctx, sel->fillColor.toCG());
    CGContextFillRect(ctx, CGRectMake(valueX, y, 40, 14));
    CGContextSetStrokeColorWithColor(ctx, Color(0.5, 0.5, 0.5).toCG());
    CGContextStrokeRect(ctx, CGRectMake(valueX, y, 40, 14));
    NSString* colorStr = [NSString stringWithFormat:@"(%.2f, %.2f, %.2f)",
                         sel->fillColor.r, sel->fillColor.g, sel->fillColor.b];
    [colorStr drawAtPoint:NSMakePoint(valueX + 45, y) withAttributes:labelAttrs];
    y += 18;
    
    [@"Stroke:" drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
    CGContextSetFillColorWithColor(ctx, sel->strokeColor.toCG());
    CGContextFillRect(ctx, CGRectMake(valueX, y, 40, 14));
    CGContextStrokeRect(ctx, CGRectMake(valueX, y, 40, 14));
    y += 24;
    
    // Animation info
    [@"🎬 Animation" drawAtPoint:NSMakePoint(padding, y) withAttributes:headerAttrs];
    y += 20;
    
    drawProp("In Frame", sel->inFrame);
    drawProp("Out Frame", sel->outFrame);
    
    NSString* tracksInfo = [NSString stringWithFormat:@"%lu tracks", (unsigned long)sel->tracks.size()];
    [@"Tracks:" drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
    [tracksInfo drawAtPoint:NSMakePoint(valueX, y) withAttributes:valueAttrs];
    y += 18;
    
    int totalKf = 0;
    for (auto& [p, t] : sel->tracks) totalKf += t.keyframes.size();
    NSString* kfInfo = [NSString stringWithFormat:@"%d keyframes", totalKf];
    [@"Keys:" drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
    [kfInfo drawAtPoint:NSMakePoint(valueX, y) withAttributes:valueAttrs];
    y += 20;
    
    // Список треков
    for (auto& [prop, track] : sel->tracks) {
        NSString* trackLabel = [NSString stringWithFormat:@"  ◆ %s (%lu kf)",
                               propertyName(prop), (unsigned long)track.keyframes.size()];
        [trackLabel drawAtPoint:NSMakePoint(padding + 8, y) withAttributes:labelAttrs];
        y += 16;
    }
}

@end

// ============================================================================
#pragma mark - Easing Preview View
// ============================================================================

@interface EasingPreviewView : NSView
@property EasingType easingType;
@end

@implementation EasingPreviewView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect b = self.bounds;
    
    CGContextSetFillColorWithColor(ctx, Color(0.12, 0.12, 0.14).toCG());
    CGContextFillRect(ctx, NSRectToCGRect(b));
    
    double pad = 20;
    double gw = b.size.width - pad*2;
    double gh = b.size.height - pad*2 - 20;
    
    // Title
    NSDictionary* attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.8 alpha:1.0]
    };
    [[NSString stringWithUTF8String:Easing::name(_easingType)]
        drawAtPoint:NSMakePoint(pad, 5) withAttributes:attrs];
    
    // Grid
    CGContextSetStrokeColorWithColor(ctx, Color(0.25, 0.25, 0.28).toCG());
    CGContextSetLineWidth(ctx, 0.5);
    CGContextStrokeRect(ctx, CGRectMake(pad, pad + 16, gw, gh));
    
    // Curve
    CGContextSetStrokeColorWithColor(ctx, Color(0.3, 0.7, 1.0, 1.0).toCG());
    CGContextSetLineWidth(ctx, 2);
    
    int steps = 100;
    for (int i = 0; i <= steps; ++i) {
        double t = (double)i / steps;
        double val = Easing::apply(_easingType, t);
        double x = pad + t * gw;
        double y = pad + 16 + gh - val * gh;
        if (i == 0) CGContextMoveToPoint(ctx, x, y);
        else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextStrokePath(ctx);
    
    // Animated ball
    double animT = fmod([[NSDate date] timeIntervalSince1970], 2.0) / 2.0;
    double easedT = Easing::apply(_easingType, animT);
    double ballX = pad + animT * gw;
    double ballY = pad + 16 + gh - easedT * gh;
    CGContextSetFillColorWithColor(ctx, Color(1.0, 0.4, 0.2, 1.0).toCG());
    CGContextFillEllipseInRect(ctx, CGRectMake(ballX - 5, ballY - 5, 10, 10));
}

@end

// ============================================================================
#pragma mark - Graph Editor View
// ============================================================================

@interface GraphEditorView : NSView
@end

@implementation GraphEditorView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect b = self.bounds;
    
    CGContextSetFillColorWithColor(ctx, Color(0.13, 0.13, 0.15).toCG());
    CGContextFillRect(ctx, NSRectToCGRect(b));
    
    auto sel = gProject.selectedObject();
    if (!sel || sel->tracks.empty()) {
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.5 alpha:1.0]
        };
        [@"Select an animated object to view curves" drawAtPoint:NSMakePoint(20, b.size.height/2 - 10)
                                                    withAttributes:attrs];
        return;
    }
    
    double pad = 30;
    double gw = b.size.width - pad*2;
    double gh = b.size.height - pad*2;
    
    // Grid
    CGContextSetStrokeColorWithColor(ctx, Color(0.22, 0.22, 0.25).toCG());
    CGContextSetLineWidth(ctx, 0.5);
    for (int i = 0; i <= 10; ++i) {
        double x = pad + (gw * i / 10.0);
        double y = pad + (gh * i / 10.0);
        CGContextMoveToPoint(ctx, x, pad); CGContextAddLineToPoint(ctx, x, pad + gh);
        CGContextMoveToPoint(ctx, pad, y); CGContextAddLineToPoint(ctx, pad + gw, y);
    }
    CGContextStrokePath(ctx);
    
    // Draw curves for each track
    Color trackColors[] = {Color::red(), Color::green(), Color::blue(), Color::yellow(),
                           Color::cyan(), Color::magenta(), Color::orange(), Color::white()};
    int colorIdx = 0;
    
    NSDictionary* labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.7 alpha:1.0]
    };
    
    for (auto& [prop, track] : sel->tracks) {
        if (track.keyframes.empty()) continue;
        
        Color col = trackColors[colorIdx % 8];
        CGContextSetStrokeColorWithColor(ctx, col.toCG());
        CGContextSetLineWidth(ctx, 1.5);
        
        // Find value range
        double minVal = 1e9, maxVal = -1e9;
        for (auto& kf : track.keyframes) {
            minVal = std::min(minVal, kf.value);
            maxVal = std::max(maxVal, kf.value);
        }
        if (maxVal - minVal < 0.001) { maxVal += 1; minVal -= 1; }
        double range = maxVal - minVal;
        
        // Draw curve
        for (int f = 0; f < gProject.totalFrames; ++f) {
            double val = track.evaluate(f);
            double x = pad + (double)f / gProject.totalFrames * gw;
            double y = pad + gh - ((val - minVal) / range) * gh;
            if (f == 0) CGContextMoveToPoint(ctx, x, y);
            else CGContextAddLineToPoint(ctx, x, y);
        }
        CGContextStrokePath(ctx);
        
        // Draw keyframe diamonds
        CGContextSetFillColorWithColor(ctx, col.toCG());
        for (auto& kf : track.keyframes) {
            double x = pad + (double)kf.frame / gProject.totalFrames * gw;
            double y = pad + gh - ((kf.value - minVal) / range) * gh;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, x, y);
            CGContextRotateCTM(ctx, Math::PI/4);
            CGContextFillRect(ctx, CGRectMake(-4, -4, 8, 8));
            CGContextRestoreGState(ctx);
        }
        
        // Label
        [[NSString stringWithFormat:@"● %s", propertyName(prop)]
            drawAtPoint:NSMakePoint(pad + 5, pad + colorIdx * 14)
            withAttributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:9],
                NSForegroundColorAttributeName: col.toNS()
            }];
        
        colorIdx++;
    }
    
    // Playhead
    double phX = pad + (double)gProject.currentFrame / gProject.totalFrames * gw;
    CGContextSetStrokeColorWithColor(ctx, Color(1, 0.3, 0.3, 0.8).toCG());
    CGContextSetLineWidth(ctx, 1);
    CGContextMoveToPoint(ctx, phX, pad);
    CGContextAddLineToPoint(ctx, phX, pad + gh);
    CGContextStrokePath(ctx);
}

@end

// ============================================================================
#pragma mark - Toolbar Delegate
// ============================================================================

@interface ToolbarController : NSObject <NSToolbarDelegate>
@property (nonatomic, weak) NSWindow* mainWindow;
@property (nonatomic, weak) CanvasView* canvasView;
@property (nonatomic, weak) TimelineView* timelineView;
@property (nonatomic, weak) InspectorView* inspectorView;
@end

@implementation ToolbarController

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)id
    willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:id];
    item.target = self;
    
    if ([id isEqual:@"play"]) {
        item.label = @"Play/Pause";
        item.image = [NSImage imageWithSystemSymbolName:@"play.fill"
                              accessibilityDescription:@"Play"];
        item.action = @selector(togglePlay:);
    } else if ([id isEqual:@"stop"]) {
        item.label = @"Stop";
        item.image = [NSImage imageWithSystemSymbolName:@"stop.fill"
                              accessibilityDescription:@"Stop"];
        item.action = @selector(stop:);
    } else if ([id isEqual:@"prevFrame"]) {
        item.label = @"Prev";
        item.image = [NSImage imageWithSystemSymbolName:@"backward.frame.fill"
                              accessibilityDescription:@"Previous Frame"];
        item.action = @selector(prevFrame:);
    } else if ([id isEqual:@"nextFrame"]) {
        item.label = @"Next";
        item.image = [NSImage imageWithSystemSymbolName:@"forward.frame.fill"
                              accessibilityDescription:@"Next Frame"];
        item.action = @selector(nextFrame:);
    } else if ([id isEqual:@"addKey"]) {
        item.label = @"Add Keyframe";
        item.image = [NSImage imageWithSystemSymbolName:@"diamond.fill"
                              accessibilityDescription:@"Add Keyframe"];
        item.action = @selector(addKeyframe:);
    } else if ([id isEqual:@"addRect"]) {
        item.label = @"Rectangle";
        item.image = [NSImage imageWithSystemSymbolName:@"rectangle.fill"
                              accessibilityDescription:@"Add Rectangle"];
        item.action = @selector(addRect:);
    } else if ([id isEqual:@"addCircle"]) {
        item.label = @"Ellipse";
        item.image = [NSImage imageWithSystemSymbolName:@"circle.fill"
                              accessibilityDescription:@"Add Circle"];
        item.action = @selector(addCircle:);
    } else if ([id isEqual:@"addStar"]) {
        item.label = @"Star";
        item.image = [NSImage imageWithSystemSymbolName:@"star.fill"
                              accessibilityDescription:@"Add Star"];
        item.action = @selector(addStar:);
    } else if ([id isEqual:@"addText"]) {
        item.label = @"Text";
        item.image = [NSImage imageWithSystemSymbolName:@"textformat"
                              accessibilityDescription:@"Add Text"];
        item.action = @selector(addText:);
    } else if ([id isEqual:@"export"]) {
        item.label = @"Export";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up"
                              accessibilityDescription:@"Export"];
        item.action = @selector(exportFrames:);
    }
    
    return item;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    return @[@"addRect", @"addCircle", @"addStar", @"addText",
             NSToolbarFlexibleSpaceItemIdentifier,
             @"prevFrame", @"play", @"stop", @"nextFrame",
             NSToolbarFlexibleSpaceItemIdentifier,
             @"addKey", @"export"];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (void)togglePlay:(id)sender {
    gProject.playing = !gProject.playing;
    [_canvasView setNeedsDisplay:YES];
}

- (void)stop:(id)sender {
    gProject.playing = NO;
    gProject.updateFrame(0);
    [_canvasView setNeedsDisplay:YES];
    [_timelineView setNeedsDisplay:YES];
}

- (void)prevFrame:(id)sender {
    if (gProject.currentFrame > 0) {
        gProject.updateFrame(gProject.currentFrame - 1);
        [self refreshAll];
    }
}

- (void)nextFrame:(id)sender {
    if (gProject.currentFrame < gProject.totalFrames - 1) {
        gProject.updateFrame(gProject.currentFrame + 1);
        [self refreshAll];
    }
}

- (void)addKeyframe:(id)sender {
    auto sel = gProject.selectedObject();
    if (!sel) return;
    
    // Добавляем keyframes для всех основных свойств
    sel->setKeyframe(PropertyType::PositionX, gProject.currentFrame, sel->transform.position.x);
    sel->setKeyframe(PropertyType::PositionY, gProject.currentFrame, sel->transform.position.y);
    sel->setKeyframe(PropertyType::Rotation, gProject.currentFrame, sel->transform.rotation);
    sel->setKeyframe(PropertyType::ScaleX, gProject.currentFrame, sel->transform.scale.x);
    sel->setKeyframe(PropertyType::ScaleY, gProject.currentFrame, sel->transform.scale.y);
    sel->setKeyframe(PropertyType::Opacity, gProject.currentFrame, sel->opacity);
    sel->setKeyframe(PropertyType::Width, gProject.currentFrame, sel->width);
    sel->setKeyframe(PropertyType::Height, gProject.currentFrame, sel->height);
    sel->setKeyframe(PropertyType::FillR, gProject.currentFrame, sel->fillColor.r);
    sel->setKeyframe(PropertyType::FillG, gProject.currentFrame, sel->fillColor.g);
    sel->setKeyframe(PropertyType::FillB, gProject.currentFrame, sel->fillColor.b);
    
    [self refreshAll];
}

- (void)addRect:(id)sender {
    auto obj = gProject.addObject(ShapeType::Rectangle, "Rectangle");
    obj->fillColor = Color::fromHSV((double)(rand() % 100) / 100.0, 0.7, 0.9);
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}

- (void)addCircle:(id)sender {
    auto obj = gProject.addObject(ShapeType::Ellipse, "Ellipse");
    obj->fillColor = Color::fromHSV((double)(rand() % 100) / 100.0, 0.7, 0.9);
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}

- (void)addStar:(id)sender {
    auto obj = gProject.addObject(ShapeType::Star, "Star");
    obj->fillColor = Color::yellow();
    obj->sides = 5;
    obj->innerRadius = 0.4;
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}

- (void)addText:(id)sender {
    auto obj = gProject.addObject(ShapeType::Text, "Text");
    obj->text = "Hello!";
    obj->fontSize = 48;
    obj->fillColor = Color::white();
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}

- (void)exportFrames:(id)sender {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = @"frame";
    panel.message = @"Export current frame as PNG";
    
    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = panel.URL;
        [self exportFrameToURL:url];
        
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Complete";
        alert.informativeText = [NSString stringWithFormat:@"Frame %d exported successfully.", gProject.currentFrame];
        [alert runModal];
    }
}

- (void)exportFrameToURL:(NSURL*)url {
    int w = gProject.canvasWidth;
    int h = gProject.canvasHeight;
    
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    
    NSGraphicsContext* gctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gctx];
    
    CGContextRef ctx = [gctx CGContext];
    
    // Фон
    CGContextSetFillColorWithColor(ctx, gProject.backgroundColor.toCG());
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    
    // Объекты
    for (auto& obj : gProject.objects) {
        if (!obj->visible) continue;
        CGContextSaveGState(ctx);
        CGContextSetAlpha(ctx, obj->opacity);
        CGAffineTransform t = obj->transform.toCG(obj->width, obj->height);
        CGContextConcatCTM(ctx, t);
        
        NSBezierPath* path = obj->createPath();
        [obj->fillColor.toNS() setFill];
        [path fill];
        if (obj->strokeWidth > 0) {
            [obj->strokeColor.toNS() setStroke];
            [path setLineWidth:obj->strokeWidth];
            [path stroke];
        }
        CGContextRestoreGState(ctx);
    }
    
    [NSGraphicsContext restoreGraphicsState];
    
    NSData* pngData = [rep representationUsingType:NSBitmapImageRepresentationTypePNG properties:@{}];
    [pngData writeToURL:url atomically:YES];
}

- (void)refreshAll {
    [_canvasView setNeedsDisplay:YES];
    [_timelineView setNeedsDisplay:YES];
    [_inspectorView setNeedsDisplay:YES];
}

@end

// ============================================================================
#pragma mark - App Delegate
// ============================================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow* window;
@property (nonatomic, strong) CanvasView* canvasView;
@property (nonatomic, strong) TimelineView* timelineView;
@property (nonatomic, strong) InspectorView* inspectorView;
@property (nonatomic, strong) GraphEditorView* graphEditorView;
@property (nonatomic, strong) EasingPreviewView* easingPreview;
@property (nonatomic, strong) ToolbarController* toolbarController;
@property (nonatomic, strong) NSTimer* animTimer;
@property (nonatomic, strong) NSTimer* displayTimer;
@property (nonatomic, strong) NSWindow* easingWindow;
@property (nonatomic, strong) NSWindow* graphWindow;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [self createDemoScene];
    [self setupMainWindow];
    [self setupMenuBar];
    [self setupTimers];
    [self setupNotifications];
    
    // Центрируем viewport
    gProject.viewOffset = {60, 30};
}

- (void)createDemoScene {
    // Создаём демо сцену с анимациями
    
    // 1. Фоновый прямоугольник
    auto bg = gProject.addObject(ShapeType::Rectangle, "Background");
    bg->transform.position = {0, 0};
    bg->width = gProject.canvasWidth;
    bg->height = gProject.canvasHeight;
    bg->fillColor = Color(0.1, 0.1, 0.2);
    bg->strokeWidth = 0;
    bg->locked = true;
    
    // 2. Анимированный круг
    auto circle = gProject.addObject(ShapeType::Ellipse, "Bouncing Ball");
    circle->width = 80;
    circle->height = 80;
    circle->fillColor = Color(0.9, 0.3, 0.2);
    circle->strokeColor = Color::white();
    circle->strokeWidth = 3;
    circle->shadow.enabled = true;
    
    circle->setKeyframe(PropertyType::PositionX, 0, 100, EasingType::EaseInOutCubic);
    circle->setKeyframe(PropertyType::PositionX, 60, 600, EasingType::EaseInOutCubic);
    circle->setKeyframe(PropertyType::PositionX, 120, 1000, EasingType::EaseInOutCubic);
    circle->setKeyframe(PropertyType::PositionX, 180, 600, EasingType::EaseInOutCubic);
    circle->setKeyframe(PropertyType::PositionX, 240, 100, EasingType::EaseInOutCubic);
    
    circle->setKeyframe(PropertyType::PositionY, 0, 300, EasingType::EaseOutBounce);
    circle->setKeyframe(PropertyType::PositionY, 60, 100, EasingType::EaseOutBounce);
    circle->setKeyframe(PropertyType::PositionY, 120, 500, EasingType::EaseOutBounce);
    circle->setKeyframe(PropertyType::PositionY, 180, 100, EasingType::EaseOutBounce);
    circle->setKeyframe(PropertyType::PositionY, 240, 300, EasingType::EaseOutBounce);
    
    circle->setKeyframe(PropertyType::ScaleX, 0, 1.0, EasingType::EaseInOutElastic);
    circle->setKeyframe(PropertyType::ScaleX, 120, 1.5, EasingType::EaseInOutElastic);
    circle->setKeyframe(PropertyType::ScaleX, 240, 1.0, EasingType::EaseInOutElastic);
    
    circle->setKeyframe(PropertyType::ScaleY, 0, 1.0, EasingType::EaseInOutElastic);
    circle->setKeyframe(PropertyType::ScaleY, 120, 1.5, EasingType::EaseInOutElastic);
    circle->setKeyframe(PropertyType::ScaleY, 240, 1.0, EasingType::EaseInOutElastic);
    
    // 3. Вращающаяся звезда
    auto star = gProject.addObject(ShapeType::Star, "Spinning Star");
    star->width = 120;
    star->height = 120;
    star->fillColor = Color(1.0, 0.85, 0.1);
    star->strokeColor = Color(0.9, 0.6, 0.0);
    star->strokeWidth = 2;
    star->sides = 5;
    star->innerRadius = 0.4;
    star->transform.position = {580, 280};
    
    star->setKeyframe(PropertyType::Rotation, 0, 0, EasingType::Linear);
    star->setKeyframe(PropertyType::Rotation, 300, 720, EasingType::Linear);
    
    star->setKeyframe(PropertyType::FillR, 0, 1.0, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillR, 100, 0.2, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillR, 200, 0.8, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillR, 300, 1.0, EasingType::EaseInOutSine);
    
    star->setKeyframe(PropertyType::FillG, 0, 0.85, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillG, 100, 0.9, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillG, 200, 0.3, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillG, 300, 0.85, EasingType::EaseInOutSine);
    
    star->setKeyframe(PropertyType::FillB, 0, 0.1, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillB, 100, 1.0, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillB, 200, 1.0, EasingType::EaseInOutSine);
    star->setKeyframe(PropertyType::FillB, 300, 0.1, EasingType::EaseInOutSine);
    
    // 4. Пульсирующий текст
    auto text = gProject.addObject(ShapeType::Text, "Title Text");
    text->text = "AnimationStudio";
    text->fontSize = 52;
    text->fontName = "Helvetica-Bold";
    text->fillColor = Color::white();
    text->transform.position = {340, 50};
    
    text->setKeyframe(PropertyType::Opacity, 0, 0.0, EasingType::EaseInOutSine);
    text->setKeyframe(PropertyType::Opacity, 30, 1.0, EasingType::EaseInOutSine);
    text->setKeyframe(PropertyType::Opacity, 270, 1.0, EasingType::EaseInOutSine);
    text->setKeyframe(PropertyType::Opacity, 300, 0.0, EasingType::EaseInOutSine);
    
    text->setKeyframe(PropertyType::ScaleX, 0, 0.5, EasingType::EaseOutBack);
    text->setKeyframe(PropertyType::ScaleX, 30, 1.0, EasingType::EaseOutBack);
    
    text->setKeyframe(PropertyType::ScaleY, 0, 0.5, EasingType::EaseOutBack);
    text->setKeyframe(PropertyType::ScaleY, 30, 1.0, EasingType::EaseOutBack);
    
    // 5. Прямоугольник с corner radius анимацией
    auto rect = gProject.addObject(ShapeType::Rectangle, "Morphing Rect");
    rect->width = 100;
    rect->height = 100;
    rect->fillColor = Color(0.2, 0.7, 0.5);
    rect->transform.position = {900, 400};
    
    rect->setKeyframe(PropertyType::CornerRadius, 0, 0, EasingType::EaseInOutCubic);
    rect->setKeyframe(PropertyType::CornerRadius, 75, 50, EasingType::EaseInOutCubic);
    rect->setKeyframe(PropertyType::CornerRadius, 150, 0, EasingType::EaseInOutCubic);
    rect->setKeyframe(PropertyType::CornerRadius, 225, 50, EasingType::EaseInOutCubic);
    rect->setKeyframe(PropertyType::CornerRadius, 300, 0, EasingType::EaseInOutCubic);
    
    rect->setKeyframe(PropertyType::Width, 0, 100, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Width, 75, 200, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Width, 150, 60, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Width, 225, 200, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Width, 300, 100, EasingType::EaseInOutElastic);
    
    rect->setKeyframe(PropertyType::Height, 0, 100, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Height, 75, 60, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Height, 150, 200, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Height, 225, 60, EasingType::EaseInOutElastic);
    rect->setKeyframe(PropertyType::Height, 300, 100, EasingType::EaseInOutElastic);
    
    // 6. Треугольник
    auto tri = gProject.addObject(ShapeType::Triangle, "Triangle");
    tri->width = 80;
    tri->height = 80;
    tri->fillColor = Color(0.6, 0.3, 0.9);
    tri->transform.position = {200, 500};
    
    tri->setKeyframe(PropertyType::PositionX, 0, 200, EasingType::EaseInOutQuad);
    tri->setKeyframe(PropertyType::PositionX, 150, 1000, EasingType::EaseInOutQuad);
    tri->setKeyframe(PropertyType::PositionX, 300, 200, EasingType::EaseInOutQuad);
    
    tri->setKeyframe(PropertyType::Rotation, 0, 0, EasingType::Linear);
    tri->setKeyframe(PropertyType::Rotation, 300, 360, EasingType::Linear);
    
    // 7. Polygon
    auto poly = gProject.addObject(ShapeType::Polygon, "Hexagon");
    poly->width = 90;
    poly->height = 90;
    poly->sides = 6;
    poly->fillColor = Color(0.2, 0.5, 0.9);
    poly->transform.position = {400, 450};
    
    poly->setKeyframe(PropertyType::Rotation, 0, 0, EasingType::Linear);
    poly->setKeyframe(PropertyType::Rotation, 300, -360, EasingType::Linear);
    
    poly->setKeyframe(PropertyType::ScaleX, 0, 1.0, EasingType::EaseInOutSine);
    poly->setKeyframe(PropertyType::ScaleX, 150, 2.0, EasingType::EaseInOutSine);
    poly->setKeyframe(PropertyType::ScaleX, 300, 1.0, EasingType::EaseInOutSine);
    
    poly->setKeyframe(PropertyType::ScaleY, 0, 1.0, EasingType::EaseInOutSine);
    poly->setKeyframe(PropertyType::ScaleY, 150, 2.0, EasingType::EaseInOutSine);
    poly->setKeyframe(PropertyType::ScaleY, 300, 1.0, EasingType::EaseInOutSine);
    
    // Добавляем систему частиц
    auto emitter = std::make_shared<ParticleEmitter>();
    emitter->position = {640, 360};
    emitter->emissionRate = 30;
    emitter->speed = 80;
    emitter->life = 2.5;
    emitter->startSize = 8;
    emitter->endSize = 1;
    emitter->startColor = Color(1.0, 0.5, 0.1, 1.0);
    emitter->endColor = Color(1.0, 0.0, 0.0, 0.0);
    emitter->gravity = {0, 50};
    gProject.emitters.push_back(emitter);
    
    gProject.selectedObjectId = circle->id;
}

- (void)setupMainWindow {
    NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
    NSRect windowRect = NSMakeRect(50, 50,
                                   std::min(1600.0, screenRect.size.width - 100),
                                   std::min(1000.0, screenRect.size.height - 100));
    
    _window = [[NSWindow alloc]
        initWithContentRect:windowRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    
    _window.title = @"AnimationStudio — Professional Animation Tool";
    _window.delegate = self;
    _window.backgroundColor = [NSColor colorWithWhite:0.15 alpha:1.0];
    _window.minSize = NSMakeSize(800, 600);
    
    NSView* contentView = _window.contentView;
    
    // Layout: Canvas | Inspector  (top)
    //         Timeline            (bottom)
    
    double inspWidth = 260;
    double timelineHeight = 200;
    double canvasWidth = contentView.bounds.size.width - inspWidth;
    double canvasHeight = contentView.bounds.size.height - timelineHeight;
    
    // Canvas
    _canvasView = [[CanvasView alloc] initWithFrame:
        NSMakeRect(0, timelineHeight, canvasWidth, canvasHeight)];
    _canvasView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:_canvasView];
    
    // Inspector (правая панель)
    NSScrollView* inspScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(canvasWidth, timelineHeight, inspWidth, canvasHeight)];
    inspScroll.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    inspScroll.hasVerticalScroller = YES;
    inspScroll.drawsBackground = NO;
    
    _inspectorView = [[InspectorView alloc] initWithFrame:
        NSMakeRect(0, 0, inspWidth, 800)];
    inspScroll.documentView = _inspectorView;
    [contentView addSubview:inspScroll];
    
    // Timeline (нижняя панель)
    NSScrollView* tlScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(0, 0, contentView.bounds.size.width, timelineHeight)];
    tlScroll.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    tlScroll.hasVerticalScroller = YES;
    tlScroll.drawsBackground = NO;
    
    _timelineView = [[TimelineView alloc] initWithFrame:
        NSMakeRect(0, 0, contentView.bounds.size.width, 600)];
    tlScroll.documentView = _timelineView;
    [contentView addSubview:tlScroll];
    
    // Разделительные линии
    NSBox* hSep = [[NSBox alloc] initWithFrame:NSMakeRect(0, timelineHeight, contentView.bounds.size.width, 1)];
    hSep.boxType = NSBoxSeparator;
    hSep.autoresizingMask = NSViewWidthSizable;
    [contentView addSubview:hSep];
    
    NSBox* vSep = [[NSBox alloc] initWithFrame:NSMakeRect(canvasWidth, timelineHeight, 1, canvasHeight)];
    vSep.boxType = NSBoxSeparator;
    vSep.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    [contentView addSubview:vSep];
    
    // Toolbar
    _toolbarController = [[ToolbarController alloc] init];
    _toolbarController.mainWindow = _window;
    _toolbarController.canvasView = _canvasView;
    _toolbarController.timelineView = _timelineView;
    _toolbarController.inspectorView = _inspectorView;
    
    NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    toolbar.delegate = _toolbarController;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    _window.toolbar = toolbar;
    
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_canvasView];
}

- (void)setupMenuBar {
    NSMenu* mainMenu = [[NSMenu alloc] init];
    
    // App menu
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"AnimationStudio"];
    [appMenu addItemWithTitle:@"About AnimationStudio" action:@selector(showAbout:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];
    
    // File menu
    NSMenuItem* fileItem = [[NSMenuItem alloc] init];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Project" action:@selector(newProject:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Export Frame..." action:@selector(exportCurrentFrame:) keyEquivalent:@"e"];
    [fileMenu addItemWithTitle:@"Export All Frames..." action:@selector(exportAllFrames:) keyEquivalent:@"E"];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];
    
    // Edit menu
    NSMenuItem* editItem = [[NSMenuItem alloc] init];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(doUndo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(doRedo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Duplicate Object" action:@selector(duplicateSelected:) keyEquivalent:@"d"];
    [editMenu addItemWithTitle:@"Delete Object" action:@selector(deleteSelected:) keyEquivalent:@"\b"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];
    
    // Object menu
    NSMenuItem* objItem = [[NSMenuItem alloc] init];
    NSMenu* objMenu = [[NSMenu alloc] initWithTitle:@"Object"];
    [objMenu addItemWithTitle:@"Add Rectangle" action:@selector(menuAddRect:) keyEquivalent:@"1"];
    [objMenu addItemWithTitle:@"Add Ellipse" action:@selector(menuAddEllipse:) keyEquivalent:@"2"];
    [objMenu addItemWithTitle:@"Add Triangle" action:@selector(menuAddTriangle:) keyEquivalent:@"3"];
    [objMenu addItemWithTitle:@"Add Star" action:@selector(menuAddStar:) keyEquivalent:@"4"];
    [objMenu addItemWithTitle:@"Add Polygon" action:@selector(menuAddPolygon:) keyEquivalent:@"5"];
    [objMenu addItemWithTitle:@"Add Line" action:@selector(menuAddLine:) keyEquivalent:@"6"];
    [objMenu addItemWithTitle:@"Add Text" action:@selector(menuAddText:) keyEquivalent:@"7"];
    [objMenu addItem:[NSMenuItem separatorItem]];
    [objMenu addItemWithTitle:@"Add Particle Emitter" action:@selector(menuAddParticles:) keyEquivalent:@"8"];
    [objMenu addItem:[NSMenuItem separatorItem]];
    [objMenu addItemWithTitle:@"Move Up" action:@selector(moveObjectUp:) keyEquivalent:@"["];
    [objMenu addItemWithTitle:@"Move Down" action:@selector(moveObjectDown:) keyEquivalent:@"]"];
    [objMenu addItemWithTitle:@"Toggle Lock" action:@selector(toggleLock:) keyEquivalent:@"l"];
    [objMenu addItemWithTitle:@"Toggle Visibility" action:@selector(toggleVisibility:) keyEquivalent:@"h"];
    objItem.submenu = objMenu;
    [mainMenu addItem:objItem];
    
    // Animation menu
    NSMenuItem* animItem = [[NSMenuItem alloc] init];
    NSMenu* animMenu = [[NSMenu alloc] initWithTitle:@"Animation"];
    [animMenu addItemWithTitle:@"Play/Pause" action:@selector(togglePlayMenu:) keyEquivalent:@" "];
    [animMenu addItemWithTitle:@"Stop" action:@selector(stopMenu:) keyEquivalent:@"."];
    [animMenu addItemWithTitle:@"Go to Start" action:@selector(goToStart:) keyEquivalent:@","];
    [animMenu addItem:[NSMenuItem separatorItem]];
    [animMenu addItemWithTitle:@"Add Keyframe (All)" action:@selector(addKeyframeAll:) keyEquivalent:@"k"];
    [animMenu addItemWithTitle:@"Add Position Keyframe" action:@selector(addPositionKey:) keyEquivalent:@""];
    [animMenu addItemWithTitle:@"Add Rotation Keyframe" action:@selector(addRotationKey:) keyEquivalent:@""];
    [animMenu addItemWithTitle:@"Add Scale Keyframe" action:@selector(addScaleKey:) keyEquivalent:@""];
    [animMenu addItemWithTitle:@"Add Opacity Keyframe" action:@selector(addOpacityKey:) keyEquivalent:@""];
    [animMenu addItem:[NSMenuItem separatorItem]];
    [animMenu addItemWithTitle:@"Set FPS..." action:@selector(setFPS:) keyEquivalent:@""];
    [animMenu addItemWithTitle:@"Set Duration..." action:@selector(setDuration:) keyEquivalent:@""];
    [animMenu addItemWithTitle:@"Set Canvas Size..." action:@selector(setCanvasSize:) keyEquivalent:@""];
    animItem.submenu = animMenu;
    [mainMenu addItem:animItem];
    
    // View menu
    NSMenuItem* viewItem = [[NSMenuItem alloc] init];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Toggle Grid" action:@selector(toggleGrid:) keyEquivalent:@"g"];
    [viewMenu addItemWithTitle:@"Toggle Snap" action:@selector(toggleSnap:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Toggle Onion Skin" action:@selector(toggleOnionSkin:) keyEquivalent:@"o"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Zoom to Fit" action:@selector(zoomFit:) keyEquivalent:@"0"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Show Graph Editor" action:@selector(showGraphEditor:) keyEquivalent:@"G"];
    [viewMenu addItemWithTitle:@"Show Easing Preview" action:@selector(showEasingPreview:) keyEquivalent:@""];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];
    
    // Window menu
    NSMenuItem* winItem = [[NSMenuItem alloc] init];
    NSMenu* winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [winMenu addItemWithTitle:@"Minimize" action:@selector(miniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Zoom" action:@selector(zoom:) keyEquivalent:@""];
    winItem.submenu = winMenu;
    [mainMenu addItem:winItem];
    
    [NSApp setMainMenu:mainMenu];
}

- (void)setupTimers {
    // Таймер анимации
    _animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer* t) {
        if (gProject.playing) {
            int nextFrame = gProject.currentFrame + 1;
            if (nextFrame >= gProject.totalFrames) {
                nextFrame = gProject.looping ? 0 : gProject.totalFrames - 1;
                if (!gProject.looping) gProject.playing = NO;
            }
            gProject.updateFrame(nextFrame);
            [self.canvasView setNeedsDisplay:YES];
            [self.timelineView setNeedsDisplay:YES];
            [self.inspectorView setNeedsDisplay:YES];
        }
        
        // Обновляем частицы даже если не playing
        for (auto& emitter : gProject.emitters) {
            if (gProject.playing) {
                emitter->update(1.0 / gProject.fps);
            }
        }
    }];
    
    // Таймер для easing preview
    _displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer* t) {
        if (self.easingPreview) [self.easingPreview setNeedsDisplay:YES];
        if (self.graphEditorView) [self.graphEditorView setNeedsDisplay:YES];
    }];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserverForName:@"Redraw" object:nil queue:nil
        usingBlock:^(NSNotification* n) {
            [self.canvasView setNeedsDisplay:YES];
        }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"SelectionChanged" object:nil queue:nil
        usingBlock:^(NSNotification* n) {
            [self.inspectorView setNeedsDisplay:YES];
            [self.canvasView setNeedsDisplay:YES];
            [self.timelineView setNeedsDisplay:YES];
        }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"FrameChanged" object:nil queue:nil
        usingBlock:^(NSNotification* n) {
            [self.timelineView setNeedsDisplay:YES];
            [self.inspectorView setNeedsDisplay:YES];
        }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"PropertyChanged" object:nil queue:nil
        usingBlock:^(NSNotification* n) {
            [self.inspectorView setNeedsDisplay:YES];
        }];
}

// Menu actions

- (void)showAbout:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"AnimationStudio";
    alert.informativeText = @"Professional Animation Tool for macOS\n\n"
        "Features:\n"
        "• Keyframe animation with 30+ easing functions\n"
        "• Multiple shape types (rect, ellipse, star, polygon, text...)\n"
        "• Timeline with multi-track editing\n"
        "• Graph editor for animation curves\n"
        "• Particle system\n"
        "• Onion skinning\n"
        "• Canvas zoom/pan\n"
        "• Snap to grid\n"
        "• Shadow & blur effects\n"
        "• 16 blend modes\n"
        "• Export to PNG\n"
        "• Undo/Redo system\n"
        "\nKeyboard Shortcuts:\n"
        "Space — Play/Pause\n"
        "← → — Navigate frames\n"
        "K — Add keyframe\n"
        "D — Duplicate\n"
        "G — Toggle grid\n"
        "O — Onion skin\n"
        "Delete — Remove object\n"
        "Cmd+Scroll — Zoom\n"
        "Alt+Drag — Pan canvas\n"
        "1-7 — Add shapes";
    [alert runModal];
}

- (void)newProject:(id)sender {
    gProject = Project();
    [self refreshAll];
}

- (void)exportCurrentFrame:(id)sender {
    [_toolbarController exportFrames:sender];
}

- (void)exportAllFrames:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.message = @"Choose folder for frame sequence export";
    
    if ([panel runModal] == NSModalResponseOK) {
        NSURL* dir = panel.URL;
        int saved = gProject.currentFrame;
        
        for (int f = 0; f < gProject.totalFrames; ++f) {
            gProject.updateFrame(f);
            NSString* fname = [NSString stringWithFormat:@"frame_%04d.png", f];
            NSURL* url = [dir URLByAppendingPathComponent:fname];
            [_toolbarController exportFrameToURL:url];
        }
        
        gProject.updateFrame(saved);
        
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"Export Complete";
        alert.informativeText = [NSString stringWithFormat:@"Exported %d frames to:\n%@",
                                gProject.totalFrames, dir.path];
        [alert runModal];
    }
}

- (void)doUndo:(id)sender { gProject.undoManager.undo(); [self refreshAll]; }
- (void)doRedo:(id)sender { gProject.undoManager.redo(); [self refreshAll]; }

- (void)duplicateSelected:(id)sender {
    if (gProject.selectedObjectId >= 0) {
        gProject.duplicateObject(gProject.selectedObjectId);
        [self refreshAll];
    }
}

- (void)deleteSelected:(id)sender {
    if (gProject.selectedObjectId >= 0) {
        gProject.removeObject(gProject.selectedObjectId);
        [self refreshAll];
    }
}

- (void)addObjectOfType:(ShapeType)type name:(const std::string&)name {
    auto obj = gProject.addObject(type, name);
    obj->fillColor = Color::fromHSV((double)(rand() % 100) / 100.0, 0.7, 0.85);
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}

- (void)menuAddRect:(id)sender     { [self addObjectOfType:ShapeType::Rectangle name:"Rectangle"]; }
- (void)menuAddEllipse:(id)sender  { [self addObjectOfType:ShapeType::Ellipse name:"Ellipse"]; }
- (void)menuAddTriangle:(id)sender { [self addObjectOfType:ShapeType::Triangle name:"Triangle"]; }
- (void)menuAddStar:(id)sender {
    auto obj = gProject.addObject(ShapeType::Star, "Star");
    obj->fillColor = Color::yellow();
    obj->sides = 5; obj->innerRadius = 0.4;
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}
- (void)menuAddPolygon:(id)sender {
    auto obj = gProject.addObject(ShapeType::Polygon, "Polygon");
    obj->fillColor = Color::fromHSV((double)(rand()%100)/100.0, 0.6, 0.8);
    obj->sides = 6;
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}
- (void)menuAddLine:(id)sender     { [self addObjectOfType:ShapeType::Line name:"Line"]; }
- (void)menuAddText:(id)sender {
    auto obj = gProject.addObject(ShapeType::Text, "Text");
    obj->text = "Text";
    obj->fontSize = 36;
    obj->fillColor = Color::white();
    gProject.selectedObjectId = obj->id;
    [self refreshAll];
}
- (void)menuAddParticles:(id)sender {
    auto emitter = std::make_shared<ParticleEmitter>();
    emitter->position = {(double)(gProject.canvasWidth/2), (double)(gProject.canvasHeight/2)};
    gProject.emitters.push_back(emitter);
    [self refreshAll];
}

- (void)moveObjectUp:(id)sender {
    gProject.moveObjectUp(gProject.selectedObjectId);
    [self refreshAll];
}
- (void)moveObjectDown:(id)sender {
    gProject.moveObjectDown(gProject.selectedObjectId);
    [self refreshAll];
}

- (void)toggleLock:(id)sender {
    if (auto sel = gProject.selectedObject()) {
        sel->locked = !sel->locked;
        [self refreshAll];
    }
}

- (void)toggleVisibility:(id)sender {
    if (auto sel = gProject.selectedObject()) {
        sel->visible = !sel->visible;
        [self refreshAll];
    }
}

- (void)togglePlayMenu:(id)sender {
    gProject.playing = !gProject.playing;
    [self refreshAll];
}

- (void)stopMenu:(id)sender {
    gProject.playing = NO;
    gProject.updateFrame(0);
    [self refreshAll];
}

- (void)goToStart:(id)sender {
    gProject.updateFrame(0);
    [self refreshAll];
}

- (void)addKeyframeAll:(id)sender {
    [_toolbarController addKeyframe:sender];
}

- (void)addPositionKey:(id)sender {
    auto sel = gProject.selectedObject();
    if (!sel) return;
    sel->setKeyframe(PropertyType::PositionX, gProject.currentFrame, sel->transform.position.x);
    sel->setKeyframe(PropertyType::PositionY, gProject.currentFrame, sel->transform.position.y);
    [self refreshAll];
}

- (void)addRotationKey:(id)sender {
    auto sel = gProject.selectedObject();
    if (!sel) return;
    sel->setKeyframe(PropertyType::Rotation, gProject.currentFrame, sel->transform.rotation);
    [self refreshAll];
}

- (void)addScaleKey:(id)sender {
    auto sel = gProject.selectedObject();
    if (!sel) return;
    sel->setKeyframe(PropertyType::ScaleX, gProject.currentFrame, sel->transform.scale.x);
    sel->setKeyframe(PropertyType::ScaleY, gProject.currentFrame, sel->transform.scale.y);
    [self refreshAll];
}

- (void)addOpacityKey:(id)sender {
    auto sel = gProject.selectedObject();
    if (!sel) return;
    sel->setKeyframe(PropertyType::Opacity, gProject.currentFrame, sel->opacity);
    [self refreshAll];
}

- (void)setFPS:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Set FPS";
    alert.informativeText = @"Enter frames per second:";
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = [NSString stringWithFormat:@"%d", gProject.fps];
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        int fps = [input.stringValue intValue];
        if (fps > 0 && fps <= 120) gProject.fps = fps;
    }
}

- (void)setDuration:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Set Duration";
    alert.informativeText = @"Enter total frames:";
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    input.stringValue = [NSString stringWithFormat:@"%d", gProject.totalFrames];
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        int frames = [input.stringValue intValue];
        if (frames > 0) gProject.totalFrames = frames;
    }
    [self refreshAll];
}

- (void)setCanvasSize:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Canvas Size";
    alert.informativeText = @"Width x Height:";
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 30)];
    NSTextField* wField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
    wField.stringValue = [NSString stringWithFormat:@"%d", gProject.canvasWidth];
    NSTextField* sep = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 0, 20, 24)];
    sep.stringValue = @"×";
    sep.editable = NO; sep.bordered = NO; sep.drawsBackground = NO;
    NSTextField* hField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 0, 80, 24)];
    hField.stringValue = [NSString stringWithFormat:@"%d", gProject.canvasHeight];
    [view addSubview:wField]; [view addSubview:sep]; [view addSubview:hField];
    alert.accessoryView = view;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        int w = [wField.stringValue intValue];
        int h = [hField.stringValue intValue];
        if (w > 0 && h > 0) { gProject.canvasWidth = w; gProject.canvasHeight = h; }
    }
    [self refreshAll];
}

- (void)toggleGrid:(id)sender { gProject.showGrid = !gProject.showGrid; [self refreshAll]; }
- (void)toggleSnap:(id)sender { gProject.snapToGrid = !gProject.snapToGrid; [self refreshAll]; }
- (void)toggleOnionSkin:(id)sender { gProject.onionSkinning = !gProject.onionSkinning; [self refreshAll]; }

- (void)zoomIn:(id)sender {
    gProject.viewZoom = Math::clamp(gProject.viewZoom * 1.25, 0.1, 10.0);
    [_canvasView setNeedsDisplay:YES];
}

- (void)zoomOut:(id)sender {
    gProject.viewZoom = Math::clamp(gProject.viewZoom / 1.25, 0.1, 10.0);
    [_canvasView setNeedsDisplay:YES];
}

- (void)zoomFit:(id)sender {
    double scaleX = (_canvasView.bounds.size.width - 100) / gProject.canvasWidth;
    double scaleY = (_canvasView.bounds.size.height - 100) / gProject.canvasHeight;
    gProject.viewZoom = std::min(scaleX, scaleY);
    gProject.viewOffset = {50, 50};
    [_canvasView setNeedsDisplay:YES];
}

- (void)showGraphEditor:(id)sender {
    if (_graphWindow) {
        [_graphWindow makeKeyAndOrderFront:nil];
        return;
    }
    _graphWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(200, 200, 700, 400)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    _graphWindow.title = @"Graph Editor";
    _graphEditorView = [[GraphEditorView alloc] initWithFrame:_graphWindow.contentView.bounds];
    _graphEditorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_graphWindow.contentView addSubview:_graphEditorView];
    [_graphWindow makeKeyAndOrderFront:nil];
}

- (void)showEasingPreview:(id)sender {
    if (_easingWindow) {
        [_easingWindow makeKeyAndOrderFront:nil];
        return;
    }
    _easingWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(300, 100, 800, 600)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    _easingWindow.title = @"Easing Functions Preview";
    
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:_easingWindow.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    
    int cols = 4;
    int count = (int)EasingType::COUNT;
    int rows = (count + cols - 1) / cols;
    double cellW = 200, cellH = 150;
    
    NSView* grid = [[NSView alloc] initWithFrame:
        NSMakeRect(0, 0, cols * cellW, rows * cellH)];
    
    for (int i = 0; i < count; ++i) {
        int col = i % cols;
        int row = i / cols;
        EasingPreviewView* preview = [[EasingPreviewView alloc]
            initWithFrame:NSMakeRect(col * cellW, row * cellH, cellW - 4, cellH - 4)];
        preview.easingType = (EasingType)i;
        [grid addSubview:preview];
    }
    
    scroll.documentView = grid;
    [_easingWindow.contentView addSubview:scroll];
    [_easingWindow makeKeyAndOrderFront:nil];
    
    _easingPreview = (EasingPreviewView*)[grid.subviews firstObject];
}

- (void)refreshAll {
    [_canvasView setNeedsDisplay:YES];
    [_timelineView setNeedsDisplay:YES];
    [_inspectorView setNeedsDisplay:YES];
    if (_graphEditorView) [_graphEditorView setNeedsDisplay:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

@end

// ============================================================================
#pragma mark - Main
// ============================================================================

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}