// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "shader_recompiler/backend/spirv/emit_spirv.h"

namespace Vulkan {

class Device;

/// Runs a cooperative matrix lowering of HMMA.16816.F16 once on known matrices and compares every
/// lane's result. Vulkan leaves the per-lane order of a cooperative matrix's elements to the driver
/// and the lowering relies on it, so a driver with another order keeps the shader emulation.
[[nodiscard]] bool TestCooperativeHmma(
    const Device& device, Shader::Backend::SPIRV::CooperativeHmmaTestPath path =
                              Shader::Backend::SPIRV::CooperativeHmmaTestPath::Registers);

} // namespace Vulkan
