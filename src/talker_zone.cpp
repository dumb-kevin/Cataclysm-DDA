#include <map>
#include <string>

#include "coordinates.h"
#include "talker_zone.h"
#include "clzones.h"
#include "debug.h"

tripoint_abs_ms talker_zone_const::pos_abs() const
{
    return me_zone_const->get_start_point();
}

