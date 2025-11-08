import { powerSaveBlocker } from 'electron';
import { Device } from '../../common/Device';

export const nullDevice: Device = {
	id: '',
	sharingSessionID: '',
	deviceOS: '',
	deviceType: '',
	deviceIP: '',
	deviceBrowser: '',
	deviceScreenWidth: -1,
	deviceScreenHeight: -1,
	deviceRoomId: '',
};

const NO_PREVENT_DISPLAY_SLEEP_ID = -1;

type ViewerConnectionAvailability = 'available' | 'occupied';

class MultipleViewerSlots {
	private devices: Map<string, Readonly<Device>> = new Map();

	occupy(device: Device): void {
		this.devices.set(device.id, Object.freeze({ ...device }));
	}

	releaseById(deviceIDToRemove: string): boolean {
		return this.devices.delete(deviceIDToRemove);
	}

	release(): void {
		this.devices.clear();
	}

	isAvailable(): boolean {
		return true; // Always available for multiple connections
	}

	snapshot(): Device[] {
		return Array.from(this.devices.values()).map(device => ({ ...device }));
	}

	isOccupiedBy(deviceID: string): boolean {
		return this.devices.has(deviceID);
	}

	count(): number {
		return this.devices.size;
	}
}

export class ConnectedDevicesService {
	private readonly slot = new MultipleViewerSlots();

	pendingConnectionDevice: Device = nullDevice;

	preventDisplaySleepId: number = NO_PREVENT_DISPLAY_SLEEP_ID;

	private readonly availabilityListeners = new Set<(state: ViewerConnectionAvailability) => void>();

	resetPendingConnectionDevice(): void {
		this.pendingConnectionDevice = nullDevice;
	}

	getDevices(): Device[] {
		return this.slot.snapshot();
	}

	isSlotAvailable(): boolean {
		return this.slot.isAvailable();
	}

	addAvailabilityListener(
		listener: (state: ViewerConnectionAvailability) => void,
	): () => void {
		this.availabilityListeners.add(listener);
		listener(this.getAvailabilityState());
		return () => {
			this.availabilityListeners.delete(listener);
		};
	}

	disconnectAllDevices(): void {
		this.slot.release();
		this.stopDisplaySleep();
		this.notifyAvailabilityListeners();
	}

	disconnectDeviceByID(deviceIDToRemove: string): Promise<undefined> {
		return new Promise<undefined>((resolve) => {
			this.slot.releaseById(deviceIDToRemove);
			if (this.slot.isAvailable()) {
				this.stopDisplaySleep();
			}
			this.notifyAvailabilityListeners();
			resolve(undefined);
		});
	}

	addDevice(device: Device): void {
		this.slot.occupy(device);
		if (this.preventDisplaySleepId === NO_PREVENT_DISPLAY_SLEEP_ID) {
			this.preventDisplaySleepId = powerSaveBlocker.start('prevent-display-sleep');
		}
		this.notifyAvailabilityListeners();
	}

	setPendingConnectionDevice(device: Device): void {
		this.pendingConnectionDevice = device;
	}

	stopDisplaySleep(): void {
		if (this.preventDisplaySleepId !== NO_PREVENT_DISPLAY_SLEEP_ID) {
			powerSaveBlocker.stop(this.preventDisplaySleepId);
			this.preventDisplaySleepId = NO_PREVENT_DISPLAY_SLEEP_ID;
		}
	}

	private getAvailabilityState(): ViewerConnectionAvailability {
		return this.slot.isAvailable() ? 'available' : 'occupied';
	}

	private notifyAvailabilityListeners(): void {
		const state = this.getAvailabilityState();
		this.availabilityListeners.forEach((listener) => {
			try {
				listener(state);
			} catch (error) {
				console.error('connected devices availability listener failed', error);
			}
		});
	}
}
