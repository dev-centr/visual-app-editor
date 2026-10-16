/// Device frames and size presets. Modes are a switcher over presets, not
/// separate layouts: the edited UI is responsive and simply re-laid-out at
/// the chosen logical size.
library;

enum DeviceMode { phone, tablet, desktop, web }

class DevicePreset {
  const DevicePreset(this.id, this.label, this.mode, this.width, this.height, {this.frame = true, this.safeTop = 0, this.safeBottom = 0});
  final String id;
  final String label;
  final DeviceMode mode;
  final double width;
  final double height;
  /// Draw a bezel around the canvas.
  final bool frame;
  final double safeTop;
  final double safeBottom;

  double get aspect => width / height;
  DevicePreset get rotated => DevicePreset('$id-rotated', '$label (landscape)', mode, height, width, frame: frame);

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'mode': mode.name, 'width': width, 'height': height};
}

class DevicePresets {
  static const all = <DevicePreset>[
    DevicePreset('phone', 'Phone 390x844', DeviceMode.phone, 390, 844, safeTop: 44, safeBottom: 30),
    DevicePreset('phone-small', 'Phone small 360x640', DeviceMode.phone, 360, 640, safeTop: 24),
    DevicePreset('phone-large', 'Phone large 430x932', DeviceMode.phone, 430, 932, safeTop: 54, safeBottom: 34),
    DevicePreset('tablet', 'Tablet 820x1180', DeviceMode.tablet, 820, 1180, safeTop: 24),
    DevicePreset('tablet-landscape', 'Tablet 1180x820', DeviceMode.tablet, 1180, 820, safeTop: 24),
    DevicePreset('desktop', 'Desktop 1280x800', DeviceMode.desktop, 1280, 800),
    DevicePreset('desktop-hd', 'Desktop 1920x1080', DeviceMode.desktop, 1920, 1080),
    DevicePreset('web', 'Web 1440x900', DeviceMode.web, 1440, 900, frame: false),
    DevicePreset('web-mobile', 'Web mobile 375x667', DeviceMode.web, 375, 667, frame: false),
  ];

  static DevicePreset byId(String id) => all.firstWhere((d) => d.id == id, orElse: () => all.first);
  static List<DevicePreset> forMode(DeviceMode m) => [for (final d in all) if (d.mode == m) d];

  /// Custom responsive size, e.g. from a width slider.
  static DevicePreset custom(double width, double height, {DeviceMode mode = DeviceMode.web}) =>
      DevicePreset('custom-${width.round()}x${height.round()}', 'Custom ${width.round()}x${height.round()}', mode, width, height, frame: false);

  /// Material-style width breakpoints used to label a size.
  static DeviceMode modeForWidth(double w) => w < 600 ? DeviceMode.phone : w < 1024 ? DeviceMode.tablet : DeviceMode.desktop;
}
