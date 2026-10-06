pub const Reflectance = enum {
    normal,
    reversed,

    pub fn isActive(self: Reflectance, logical_dark: bool) bool {
        return switch (self) {
            .normal => logical_dark,
            .reversed => !logical_dark,
        };
    }
};
