sudo docker run \
	--runtime nvidia \
	-it \
	--rm \
	--network host  \
	--privileged \
	-v /dev:/dev  \
	-v "$(pwd)/src":/developer_ws/src \
	-v "$(pwd)/files_to_container":/files_to_container \
	-v "$HOME/ros-docker/ros2_custom_config_setup:/ros2_custom_config_setup" \
	unitree-hackathon	
