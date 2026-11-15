class_name FluidKit
extends RefCounted

## Plugin metadata and the group names the runtime uses, so game-side code can
## find the fluid systems without hard-coding strings.
##
##   FluidKit.VERSION            plugin version
##   FluidKit.ATMOSPHERE_GROUP   the Atmosphere node (gas field owner)
##   FluidKit.VENT_GROUP         static GasVent nozzles
##   FluidKit.FIELD_GROUP        per-room GasField configuration markers
##   FluidKit.LIGHT_GROUP        FogLight gas lights
##   FluidKit.TRAIL_GROUP        GasTrailWalker style moving emitters

const VERSION := "1.0.0"
const ATMOSPHERE_GROUP := &"atmosphere"
const VENT_GROUP := &"gas_vent"
const FIELD_GROUP := &"gas_field"
const LIGHT_GROUP := &"fog_light"
const TRAIL_GROUP := &"gas_trail_walker"
