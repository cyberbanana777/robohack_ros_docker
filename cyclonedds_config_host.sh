echo "<<= Cyclonedds configurated for work with Jetson =>>"

# base invironment
source /opt/ros/foxy/install/setup.bash

# dds setup
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces>
                            <NetworkInterface name="l4tbr0" priority="default" multicast="default" />
                        </Interfaces></General></Domain></CycloneDDS>'


