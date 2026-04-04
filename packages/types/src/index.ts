// User Types
export interface User {
  id: string;
  email: string;
  name: string;
  createdAt: Date;
  updatedAt: Date;
}

// Hive Types
export interface Hive {
  id: string;
  userId: string;
  name: string;
  location: string;
  createdAt: Date;
  updatedAt: Date;
}

// Analysis Types
export interface AnalysisRequest {
  hiveId: string;
  imageUrl: string;
}

export interface AnalysisResult {
  id: string;
  hiveId: string;
  varroaInfectionRisk: number; // 0-100
  estimatedVarroaCount: number;
  overallHealth: 'healthy' | 'warning' | 'critical';
  recommendations: string[];
  analyzedAt: Date;
}

// Report Types
export interface Report {
  id: string;
  hiveId: string;
  analyses: AnalysisResult[];
  generatedAt: Date;
}

// Subscription Types
export interface Subscription {
  id: string;
  userId: string;
  plan: 'free' | 'basic' | 'pro';
  status: 'active' | 'inactive' | 'cancelled';
  startDate: Date;
  endDate?: Date;
}
