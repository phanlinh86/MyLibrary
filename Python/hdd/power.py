import ftd2xx as ft
import time

class Switch(object):
    """Class to control HDD power supply using FTDI device in bitbang mode."""

    ON = 0xB1  # bit mask to turn adapter on
    OFF = 0x71  # bit mask to turn adapter off

    def __init__(self, id=None):
        """Initialize the HDD switch."""
        self._id = id # Default ID for the FTDI device
        self._dev = None  # Device handle, will be set during initialization
        self._serial = None  # Serial number, not used in this implementation
        self._description = None  # Description, not used in this implementation
        self._state = None  # State of the switch, not used in this implementation

    def init(self):
        """Initialize the FTDI device."""
        try:
            self._dev = ft.open(self._id)  # Open the FTDI device with the specified ID
            # Get the device information
            info = self._dev.getDeviceInfo()
            self._serial = info['serial']
            self._description = info['description']
            print(f"FTDI device initialized successfully with ID: {self._id}")
        except Exception as e:
            print(f"Error initializing FTDI device: {e}")
            self._dev = None


    """ Read-only properties of the FTDI device. """
    @property
    def id(self):
        """Get the ID of the FTDI device."""
        return self._id

    @property
    def dev(self):
        """Get the FTDI device handle."""
        return self._dev

    @property
    def serial(self):
        """Get the ID of the FTDI device."""
        return self._id

    @property
    def description(self):
        """Get the description of the FTDI device."""
        return self._description

    """ FTDI termination functions. """
    def close(self):
        """Close the FTDI device."""
        if self._dev:
            try:
                self._dev.close()
                print("FTDI device closed successfully.")
            except Exception as e:
                print(f"Error closing FTDI device: {e}")
        else:
            print("No FTDI device to close.")

    def __del__(self):
        """Destructor to ensure the device is closed when the object is deleted."""
        self.close()

    """ State switching """
    def state(self, newState=None):
        """Switch the HDD power supply state.

        Args:
            state (int): 1 to turn ON, 0 to turn OFF. None to read the current state.
        """
        if self._dev is None:
            print("Device not initialized. Call initialize_ftdi() first.")
            return

        if newState is None:
            return self.read()

        if newState not in (0, 1):
            print("Invalid state. Use 1 to turn ON and 0 to turn OFF.")
            return

        try:
            if newState == 0:
                self._dev.setBitMode(self.OFF, 1)
            else:
                self._dev.setBitMode(self.ON, 1)
            self._state = newState
            print(f"HDD Power Supply turned {'ON' if newState == 1 else 'OFF'}")
        except Exception as e:
            print(f"Error switching power state: {e}")

    def read(self):
        """Read the current state of the HDD switch.

        Returns:
            int: Current state (1 for ON, 0 for OFF).
        """
        if self._dev is None:
            print("Device not initialized. Call initialize_ftdi() first.")
            return None

        try:
            # Read the current state from the FTDI device
            state = self._dev.getBitMode()
            # GetBitMode returns NOT of the current state, so we need to invert it
            state = ~state & 0xFF  # Mask to get the last 8
            self._state = state
            if state == self.ON:
                print("HDD Power Supply is ON")
                return 1
            elif state == self.OFF:
                print("HDD Power Supply is OFF")
                return 0
            else:
                print("HDD Power Supply state is UNKNOWN")
                return None

        except Exception as e:
            print(f"Error reading power state: {e}")
            return None

    """ Others functions. """
    def __str__(self):
        """String representation of the HDD switch."""
        return f"HDD Switch (ID: {self._id}, Serial: {self._serial}, Description: {self._description}), State: {'ON' if self._state == 1 else 'OFF' if self._state == 0 else 'Unknown'})"


if __name__ == "__main__":
    switch = Switch(0)  # Create an instance of HddSwitch with default ID
    switch.init()  # Initialize the FTDI device
    print(f"State before switching: {switch.read()}")  # Read the current state
    switch.state(1)  # Turn ON the HDD power supply
    time.sleep(1)  # Keep it ON for 5 seconds
    switch.state(0)  # Turn ON the HDD power supply
    print(switch)  # Print the HDD switch status
    # Note: The __del__ method will automatically close the device when the object is deleted
    # main()