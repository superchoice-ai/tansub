/** Product choices for new applications. Historical vehicles keep their original type labels. */
export const LOAN_TYPE_LABEL: Record<string, string> = {
  car: "รถยนต์",
  motorcycle: "รถจักรยานยนต์",
  personal: "สินเชื่อบุคคล",
  car_insurance: "สินเชื่อประกันภัยรถยนต์",
  gold: "สินเชื่อทอง",
  other: "อื่นๆ",
};

export function isVehicleLoan(type: string): boolean {
  return type === "car" || type === "motorcycle";
}

/** Staff enters only this segment; the database generates the document number. */
export function normalizeLoanSubtype(value: string): string {
  const normalized = value.trim().toUpperCase();
  if (!/^[A-Z]{1,4}$/.test(normalized)) {
    throw new Error("กรุณากรอกอักษรในเลขคำขอ A–Z จำนวน 1–4 ตัว");
  }
  return normalized;
}
