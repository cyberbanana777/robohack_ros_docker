
# --- This file can be edited. ---

# base invironment
source /opt/ros/foxy/install/setup.bash

# dds setup
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
#export CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces>
#                            <NetworkInterface name="l4tbr0" priority="default" multicast="default" />
#                        </Interfaces></General></Domain></CycloneDDS>'


if [ -f /developer_ws/install/setup.bash ]; then
    source /developer_ws/install/setup.bash
fi

